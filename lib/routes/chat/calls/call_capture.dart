import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_tap.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';

/// Where a completed chunk goes.
///
/// An interface rather than a direct HTTP call so the capture path can be tested
/// by feeding it audio and reading back what it produced, and so a delivery
/// failure is the sink's problem rather than the recorder's.
abstract class CallAudioSink {
  /// Delivers one chunk. Safe to call again with the same chunk: the server keys
  /// a result by capture session and chunk index, so a redelivery credits
  /// nothing twice.
  ///
  /// [within] is how long the attempt itself may take. Given to the sink rather
  /// than applied by the caller because it has to bound the WORK: a caller that
  /// merely stopped waiting leaves the attempt running, and a retry that joins
  /// it is not a second attempt at all.
  Future<void> deliver(PcmChunk chunk, {Duration? within});

  /// Signals that no further chunks are coming for this call.
  ///
  /// Returns whether every outstanding transcription settled. FALSE means the
  /// sink gave up on work still in flight, so what it holds is knowingly short
  /// of what was said. It used to return nothing and merely log that, which
  /// left the one caller that publishes a transcript unable to tell a complete
  /// half from a truncated one -- and a half that quietly claims to be
  /// everything somebody said is the one outcome this feature cannot produce.
  Future<bool> close();
}

/// The audio format chunks are captured and delivered in.
///
/// 16 kHz mono is what speech-to-text providers accept natively, so nothing
/// downstream resamples, and it keeps a chunk small enough that the route's
/// request cap is never the binding constraint.
const captureSampleRate = 16000;
const captureChannels = 1;

/// How many times a chunk's delivery is attempted.
///
/// A chunk is up to ninety seconds of somebody's speech and there is no second
/// copy — the call is over by the time delivery fails, and nothing can record
/// it again.
const _deliveryAttempts = 3;

/// How long one attempt at delivering a chunk is given.
///
/// A request that fails says so; one that hangs says nothing, and a hangup waits
/// for every chunk still in flight. Without a limit here a single stalled
/// connection would hold the end of the call open indefinitely.
const _deliveryTimeout = Duration(seconds: 30);

/// How long a stop waits for chunks already handed over.
///
/// Long enough for an ordinary delivery and its first retry, short enough that
/// a stuck upload cannot hold up the next stretch of recording.
const _settleDeliveriesWithin = Duration(seconds: 10);

/// How long the END of a call waits for deliveries still in flight. Generous —
/// it covers a delivery's full retry budget — because this is the last chance
/// for the words to land; but finite, because a record that never appears is
/// worse than one slightly short.
const _settleFinishWithin = Duration(minutes: 2);

/// How long a tap is given to come off before it is treated as stuck.
///
/// Detaching is a platform call and should take no time at all, but teardown
/// waits on it — and a hangup that never finishes never writes the call, so the
/// learner loses both the record and every word of the conversation.
const _detachTimeout = Duration(seconds: 5);

/// Records this device's own outbound call audio.
///
/// It taps the track being published, not the microphone. A microphone also
/// hears the peer coming back out of the speaker, and every word that bled
/// through would be credited to the wrong learner — so the tap point is the
/// requirement, not an implementation preference.
///
/// One recorder per call. Starting a second while one runs is a caller error
/// rather than a silent second recording.
class CallCaptureService {
  final CallAudioSink sink;
  final CallAudioTap tap;
  final Duration deliveryTimeout;

  /// How long a tap is given to detach. Injected so a test need not wait it out.
  final Duration detachTimeout;
  final PcmChunker Function(int firstIndex, int sampleRate) _newChunker;

  /// Chunk numbering continues across stop and start. Recording can be handed to
  /// another of the learner's devices and handed back within one call, and a
  /// second stretch numbered from zero would be taken for a redelivery of the
  /// first and silently dropped.
  int _nextIndex = 0;

  PcmChunker? _chunker;
  DetachTap? _detach;
  bool _stopping = false;

  /// Whether a tap is attached. Separate from having a chunker, because the rate
  /// is not known until audio actually arrives.
  bool _running = false;

  /// Which stretch of recording this is. Attaching a tap takes a round trip and
  /// a stop can land inside it; comparing this afterwards is how that stop is
  /// noticed, rather than storing a tap nothing is left tracking.
  int _session = 0;

  /// Chunks handed to the sink but not yet acknowledged. Awaited on [stop] so a
  /// hangup does not abandon audio the learner already spoke.
  final List<Future<void>> _inFlight = [];

  /// [deliveryTimeout] is how long one attempt is given before it is treated as
  /// failed. Injectable so the stall can be tested without waiting for it.
  CallCaptureService({
    required this.sink,
    CallAudioTap? tap,
    this.deliveryTimeout = _deliveryTimeout,
    this.detachTimeout = _detachTimeout,
    PcmChunker Function(int firstIndex, int sampleRate)? newChunker,
  }) : tap =
           tap ??
           defaultCallAudioTap(
             sampleRate: captureSampleRate,
             channels: captureChannels,
           ),
       _newChunker =
           newChunker ??
           ((firstIndex, sampleRate) => PcmChunker(
             sampleRate: sampleRate,
             channels: captureChannels,
             firstIndex: firstIndex,
           ));

  /// Taps that have not come off. A recording will not start while this has
  /// anything in it.
  ///
  /// Each carries what is still running, when something is: a detach that timed
  /// out has NOT stopped, and asking the same closure again would run a second
  /// stop over the top of the first. The next attempt waits for what is already
  /// in flight instead, and only re-asks a detach that actually threw.
  final List<_UnreleasedTap> _unreleased = [];

  bool get isRecording => _running;

  /// Begins recording [track].
  ///
  /// Requests the capture format explicitly rather than accepting whatever the
  /// device happens to produce, so a chunk's bytes mean the same thing on every
  /// platform and the header we write over them is always true.
  Future<void> start(AudioTrack track) async {
    if (_running) {
      throw StateError('A call recording is already running');
    }
    if (_detach != null || _unreleased.isNotEmpty) {
      // A previous tap never detached. Refuse rather than stack a second tap on
      // the same track: losing this stretch of analytics is recoverable,
      // counting it twice is not.
      throw StateError('The previous audio tap is still attached');
    }
    _stopping = false;
    _stopped = null;
    _running = true;
    final session = ++_session;
    final DetachTap? detach;
    try {
      detach = await tap.open(track, _onFrames);
    } catch (_) {
      // Left clear so a transient failure can be retried by the next election.
      // Recording as started forever would refuse every later attempt.
      if (_session == session) _running = false;
      rethrow;
    }
    if (_session != session) {
      // A stop landed while this was attaching. The tap belongs to a recording
      // that is already over, so it is released here rather than stored: by the
      // time it arrived another recording may already own [_detach], and writing
      // over that would leave the live tap untracked.
      await _release(detach);
      return;
    }
    _detach = detach;
    if (detach == null) {
      // No tap on this device. Nothing is recorded, and the call is unaffected.
      _running = false;
    }
  }

  /// Lets go of a tap, and does not lose it if it will not let go.
  ///
  /// The only way a tap is ever released. A detach that throws has left the tap
  /// attached to the track, so it is kept rather than dropped: the next stop
  /// tries it again, and until one succeeds no new recording may start over the
  /// top of it — two taps feeding one chunker would count the learner's own
  /// voice twice.
  ///
  /// Held in a list rather than back in [_detach] because there can genuinely be
  /// more than one: a tap arriving late from an [start] that a stop overtook is
  /// not the tap the current recording owns, and the two must not displace each
  /// other.
  Future<void> _release(DetachTap? detach) async {
    if (detach == null) return;
    // Invoked inside a guard, and through Future.value because a tap may detach
    // synchronously — the renderer's cancel does. It may also THROW
    // synchronously, and called outside a guard that throw escaped this method
    // altogether: the tap was never retained, so nothing ever came back to it
    // and it stayed attached in silence.
    final Future<void> running;
    try {
      running = Future.value(detach());
    } catch (e, s) {
      // It threw before it returned anything at all. Nothing is in flight, and
      // the tap is certainly still attached.
      _hold(_UnreleasedTap(detach, null));
      Logs().w('Could not detach the call audio tap; it stays claimed', e, s);
      return;
    }
    // Read from a flag rather than by catching TimeoutException. The LiveKit
    // package exports its own class of that name, and this file imports it for
    // AudioTrack, so `on TimeoutException` here binds to LiveKit's and silently
    // never matches the one dart:async throws — every timeout took the path
    // meant for a tap that threw, and the tap was asked to detach a second time
    // while the first was still running. Any file in this feature that imports
    // livekit_client has the same trap.
    var stillRunning = false;
    try {
      // Bounded, because teardown waits on this. A platform call that never
      // came back left the hangup unfinished for good: the call was never
      // written and every word of it went uncredited, to protect a tap that
      // was already lost either way.
      await running.timeout(
        detachTimeout,
        onTimeout: () => stillRunning = true,
      );
    } catch (e, s) {
      // It threw, so nothing is running and the tap is certainly still on. This
      // one is worth asking again.
      _hold(_UnreleasedTap(detach, null));
      Logs().w('Could not detach the call audio tap; it stays claimed', e, s);
      return;
    }
    if (stillRunning) {
      // Kept along with what is running, so the next stop waits for THAT rather
      // than starting a second detach over the top of it.
      _hold(_UnreleasedTap(detach, running));
      Logs().w('The call audio tap has not come off yet; it stays claimed');
    }
  }

  /// Holds a tap that has not come off, and lets go of it the moment it does.
  ///
  /// Only a stop ever comes back to these, and a stop happens at the END of a
  /// call — so a tap that timed out and then detached a second later would
  /// otherwise block every recorder election for the rest of the call, and this
  /// device would sit silent through the whole conversation.
  void _hold(_UnreleasedTap tap) {
    _unreleased.add(tap);
    tap.running
        ?.then((_) => _unreleased.removeWhere((held) => identical(held, tap)))
        // An error means it answered too: it is no longer in flight, so it may
        // be asked again, which is what an entry with nothing running means.
        .onError((Object _, StackTrace _) {
          final at = _unreleased.indexWhere((held) => identical(held, tap));
          if (at >= 0) _unreleased[at] = _UnreleasedTap(tap.detach, null);
        });
  }

  /// Tries the taps that would not let go before. Taken and cleared first, so a
  /// failure adds itself back for next time rather than being retried forever
  /// inside this loop.
  Future<void> _releaseUnreleased() async {
    if (_unreleased.isEmpty) return;
    final pending = List.of(_unreleased);
    _unreleased.clear();
    for (final tap in pending) {
      final running = tap.running;
      if (running == null) {
        // It threw last time; nothing is in flight, so ask again.
        await _release(tap.detach);
        continue;
      }
      var stillRunning = false;
      try {
        // Already running. Waiting is the only safe thing: asking again would
        // stop the platform capture a second time while the first stop is
        // still going.
        await running.timeout(
          detachTimeout,
          onTimeout: () => stillRunning = true,
        );
      } catch (e, s) {
        // It finally answered, with an error. Nothing is running now, so the
        // next stop may ask again.
        _hold(_UnreleasedTap(tap.detach, null));
        Logs().w('The call audio tap refused to come off', e, s);
        continue;
      }
      if (stillRunning) {
        _hold(tap);
        Logs().w('The call audio tap has still not come off');
      }
    }
  }

  /// Takes audio from the tap.
  ///
  /// The chunker is built here rather than at start, because the rate is not
  /// known until audio arrives — and it can change mid-call when the device or
  /// the negotiated codec does. A change ends the current chunk rather than
  /// reinterpreting samples already collected at the old rate, which would
  /// stretch or compress what the learner said.
  /// Whether the learner has muted. Frames are dropped while it is set.
  ///
  /// A gate the recorder owns, NOT LiveKit's mute. LiveKit's mute only stops
  /// PUBLISHING to the peer; on Android this tap reads the audio module's
  /// capture output directly, upstream of that, and `stopAudioCaptureOnMute` is
  /// off so the module keeps running — so without this a muted learner would
  /// still be recorded and transcribed. Dropping the frames means a mute is a
  /// gap in the transcript, which is what a mute should be.
  bool _muted = false;

  /// Gates or ungates capture to match the microphone button.
  void setMuted(bool muted) => _muted = muted;

  void _onFrames(Int16List samples, int sampleRate) {
    if (!_running || _stopping || _muted) return;
    var chunker = _chunker;
    if (chunker != null && chunker.sampleRate != sampleRate) {
      final tail = chunker.flush();
      if (tail != null) _hand(tail);
      _nextIndex = chunker.nextIndex;
      chunker = null;
    }
    chunker ??= _chunker = _newChunker(_nextIndex, sampleRate);
    for (final chunk in chunker.add(samples)) {
      _hand(chunk);
    }
  }

  void _hand(PcmChunk chunk) {
    late final Future<void> delivery;
    delivery = _deliver(chunk).whenComplete(() => _inFlight.remove(delivery));
    _inFlight.add(delivery);
  }

  /// Delivers a chunk, retrying a failure rather than dropping it.
  ///
  /// One request lost on a weak connection — ordinary on mobile — used to cost
  /// up to ninety seconds of a learner's speech silently, and it fell hardest on
  /// exactly the people with the worst connections. The attempts are bounded and
  /// backed off: a chunk that will never send must not hold a hangup open.
  ///
  /// Never throws. A chunk that cannot be delivered costs its share of the
  /// transcript; it must not take the call down with it.
  Future<void> _deliver(PcmChunk chunk) async {
    for (var attempt = 0; attempt < _deliveryAttempts; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(seconds: attempt));
      try {
        await sink.deliver(chunk, within: deliveryTimeout);
        return;
      } catch (e, s) {
        Logs().w(
          'Call audio chunk ${chunk.index} delivery attempt '
          '${attempt + 1} of $_deliveryAttempts failed',
          e,
          s,
        );
      }
    }
    Logs().e(
      'Gave up delivering call audio chunk ${chunk.index}; its words are lost',
    );
  }

  /// Stops recording, flushes the tail, and waits for delivery to settle.
  ///
  /// Idempotent, because a hangup and a disconnect can both land: the tap is
  /// cancelled and the chunker cleared before anything is awaited, so a second
  /// call has nothing left to flush and cannot emit a duplicate tail.
  /// The stop in flight, so two callers join one rather than both running it.
  /// A hangup and a disconnect routinely arrive together, and a check followed
  /// by an await lets both past.
  Future<void>? _stopped;

  /// Ends this stretch of recording.
  ///
  /// [settleDeliveries] waits, briefly, for chunks already handed to the sink.
  /// Teardown passes false: the transcripts go to choreo, and a call is over
  /// when the microphone and the membership are released, never when a
  /// transcription answers. Waiting here held the account's one call open for
  /// as long as choreo took -- which refused the next call and, worse, silently
  /// swallowed an INCOMING ring, because a ring that arrives while this account
  /// reads as busy is dropped from the stream and never replayed.
  ///
  /// Nothing is abandoned by skipping it: [finish] awaits the very same futures
  /// straight afterwards with a far longer bound, and every delivery keeps its
  /// own retry path regardless.
  ///
  /// Only the LOCAL stop is shared between callers. Two of them may want
  /// different settling -- a recorder handover wants it, a hangup does not --
  /// and a memoised whole would have made the second caller inherit the first's
  /// choice, which is how a hangup came to wait out a handover's drain.
  Future<void> stop({bool settleDeliveries = true}) async {
    await (_stopped ??= _stop().whenComplete(() => _stopped = null));
    if (settleDeliveries) await _settle(_settleDeliveriesWithin);
  }

  /// Waits for what has already been handed to the sink, bounded.
  ///
  /// The bound applies to the WAITING, never to the audio: each delivery keeps
  /// its own retry path, and nothing here truncates or drops a chunk.
  Future<void> _settle(Duration within) async {
    try {
      await Future.wait(List.of(_inFlight)).timeout(within);
    } catch (e, s) {
      Logs().w('Chunks were still on their way when recording settled', e, s);
    }
  }

  Future<void> _stop() async {
    // Checked against the taps as well as the chunker: a call can be attached
    // with no chunker yet, because the chunker is not built until audio actually
    // arrives, and returning early there would leave the tap attached. A tap
    // that would not let go counts too — this is the only thing that ever comes
    // back to one, so returning above it would strand it for good.
    if (!_running &&
        _chunker == null &&
        _detach == null &&
        _unreleased.isEmpty) {
      return;
    }
    _session++;

    // Stop taking frames NOW, before the detach, not after it. Detaching a tap
    // is a platform round-trip that can take its bounded seconds to answer, and
    // every frame that arrived while it ran used to be chunked — which after a
    // hangup is post-hangup microphone audio, the learner's private
    // conversation once they believed the call was over. That is the one place
    // this feature must never leak, so frames are refused here first. The cost
    // is at most the tap's last un-flushed batch; everything the learner said up
    // to this line is already in the chunker and is flushed below.
    _stopping = true;
    _running = false;

    // Taken and cleared BEFORE it is awaited. Leaving it set across the await
    // let a second stop past the guard above and detach the same tap twice.
    final detach = _detach;
    _detach = null;
    await _release(detach);
    // And another go at anything that would not let go earlier. A tap detaches
    // on the next stop or not at all; nothing else ever comes back to it.
    await _releaseUnreleased();

    final chunker = _chunker;
    _chunker = null;

    if (chunker != null) {
      final tail = chunker.flush();
      if (tail != null) _hand(tail);
      // Remembered before the chunker is let go, so a later stretch of the same
      // call numbers on from here.
      _nextIndex = chunker.nextIndex;
    }
  }

  /// Ends the call's recording for good.
  ///
  /// Separate from [stop], which ends one stretch of it. Recording moves between
  /// a learner's devices during a call and comes back, so a stretch ending is
  /// not the audio ending — and telling the sink otherwise, while chunks
  /// numbered on from there were still to come, was a promise this could not
  /// keep.
  Future<void> finish() =>
      _finishing ??= _finish().whenComplete(() => _finishing = null);

  /// The finish in flight, so two callers join one. Cleared on completion, so a
  /// close that failed can still be retried.
  Future<void>? _finishing;

  Future<void> _finish() async {
    // Without settling: this is the one caller that is ABOUT to settle, with a
    // far longer bound. Letting stop settle first would serve a ten second wait
    // and then a two minute one back to back, for the same futures, delaying
    // the transcripts and the analytics credited from them for no reason.
    await stop(settleDeliveries: false);
    if (_finished) return;
    // Everything still on its way — but BOUNDED, like every other wait in a
    // call's life. The bound applies to the WAITING, never to the audio: each
    // delivery keeps its own retry path, and nothing here truncates a chunk.
    // Deliveries are individually bounded (attempts x deliveryTimeout), so this
    // outer bound only fires if something violates that contract — and when it
    // does, the record is still written with what landed, because a record
    // slightly short is strictly better than one that never appears. The chunks
    // still outstanding are logged as lost.
    try {
      await Future.wait(List.of(_inFlight)).timeout(_settleFinishWithin);
    } catch (e, s) {
      Logs().w(
        'A call audio chunk never landed before the finish gave up',
        e,
        s,
      );
    }
    // Marked only once it has actually happened. Marking first meant a close
    // that failed was remembered as done, and the retry that could have fixed
    // it skipped the work — the same mistake as clearing a handle before the
    // operation it stands for has succeeded.
    await sink.close();
    _finished = true;
  }

  bool _finished = false;

  /// The frame's samples as 16-bit PCM. Lives with the tap that produces them.
  @visibleForTesting
  static Int16List pcmOf(AudioFrame frame) => pcmOfFrame(frame);
}

/// A tap that has not come off, and what is still trying, if anything is.
class _UnreleasedTap {
  final DetachTap detach;

  /// The detach already in flight. Null when it threw rather than hung, which
  /// is the only case where asking again is safe.
  final Future<void>? running;

  const _UnreleasedTap(this.detach, this.running);
}
