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
  Future<void> deliver(PcmChunk chunk);

  /// Signals that no further chunks are coming for this call.
  Future<void> close();
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
    if (_detach != null) {
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
      // that is already over, so it is released here — storing it would leave it
      // attached with nothing tracking it.
      await detach?.call();
      return;
    }
    _detach = detach;
    if (detach == null) {
      // No tap on this device. Nothing is recorded, and the call is unaffected.
      _running = false;
    }
  }

  /// Takes audio from the tap.
  ///
  /// The chunker is built here rather than at start, because the rate is not
  /// known until audio arrives — and it can change mid-call when the device or
  /// the negotiated codec does. A change ends the current chunk rather than
  /// reinterpreting samples already collected at the old rate, which would
  /// stretch or compress what the learner said.
  void _onFrames(Int16List samples, int sampleRate) {
    if (!_running || _stopping) return;
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
        await sink.deliver(chunk).timeout(deliveryTimeout);
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

  Future<void> stop() =>
      _stopped ??= _stop().whenComplete(() => _stopped = null);

  Future<void> _stop() async {
    // Checked against the tap as well as the chunker: a call can be attached
    // with no chunker yet, because the chunker is not built until audio actually
    // arrives, and returning early there would leave the tap attached.
    if (!_running && _chunker == null && _detach == null) return;
    _session++;

    // A tap that will not detach must not cost the tail. The frames it may still
    // deliver are already ignored, so the worst case is a tap left registered —
    // losing the last seconds of what the learner said is the more expensive
    // failure.
    // Taken and cleared BEFORE it is awaited. Leaving it set across the await
    // let a second stop past the guard above and detach the same tap twice.
    final detach = _detach;
    _detach = null;
    try {
      // Audio is still accepted while this runs. Detaching is what makes a tap
      // hand over the last of what it gathered, and that tail is the end of a
      // sentence — refusing frames first would collect it and then throw it
      // away.
      await detach?.call();
    } catch (e, s) {
      // Put back, not discarded. A tap that would not detach is still attached,
      // and starting again over the top of it would feed two taps into one
      // chunker — the learner's own voice counted twice.
      _detach = detach;
      Logs().w('Could not detach the call audio tap; it stays claimed', e, s);
    }

    // Only now: nothing more can arrive, so what is held is the whole of it.
    _stopping = true;
    _running = false;
    final chunker = _chunker;
    _chunker = null;

    if (chunker != null) {
      final tail = chunker.flush();
      if (tail != null) _hand(tail);
      // Remembered before the chunker is let go, so a later stretch of the same
      // call numbers on from here.
      _nextIndex = chunker.nextIndex;
    }

    await Future.wait(List.of(_inFlight));
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
    await stop();
    if (_finished) return;
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
