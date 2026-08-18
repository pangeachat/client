import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:matrix/matrix.dart';

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
  final PcmChunker Function(int firstIndex) _newChunker;

  /// Chunk numbering continues across stop and start. Recording can be handed to
  /// another of the learner's devices and handed back within one call, and a
  /// second stretch numbered from zero would be taken for a redelivery of the
  /// first and silently dropped.
  int _nextIndex = 0;

  PcmChunker? _chunker;
  CancelListenFunc? _cancelTap;
  bool _stopping = false;

  /// Chunks handed to the sink but not yet acknowledged. Awaited on [stop] so a
  /// hangup does not abandon audio the learner already spoke.
  final List<Future<void>> _inFlight = [];

  CallCaptureService({
    required this.sink,
    PcmChunker Function(int firstIndex)? newChunker,
  }) : _newChunker =
           newChunker ??
           ((firstIndex) => PcmChunker(
             sampleRate: captureSampleRate,
             channels: captureChannels,
             firstIndex: firstIndex,
           ));

  bool get isRecording => _chunker != null;

  /// Begins recording [track].
  ///
  /// Requests the capture format explicitly rather than accepting whatever the
  /// device happens to produce, so a chunk's bytes mean the same thing on every
  /// platform and the header we write over them is always true.
  void start(AudioTrack track) {
    if (isRecording) {
      throw StateError('A call recording is already running');
    }
    if (_cancelTap != null) {
      // A previous tap never detached. Try once more, and refuse rather than
      // stack a second renderer on the same track: losing this stretch of
      // analytics is recoverable, counting it twice is not.
      throw StateError('The previous audio tap is still attached');
    }
    _stopping = false;
    final chunker = _newChunker(_nextIndex);
    try {
      // Registered before anything is recorded as running. A tap that throws
      // half-way would otherwise leave this looking started forever, and every
      // later attempt would be refused by the guard above — costing the call its
      // analytics for a failure that was transient.
      _cancelTap = track.addAudioRenderer(
        onFrame: _onFrame,
        options: const AudioRendererOptions(
          sampleRate: captureSampleRate,
          channels: captureChannels,
          format: AudioFormat.Int16,
        ),
      );
    } catch (_) {
      _cancelTap = null;
      rethrow;
    }
    _chunker = chunker;
  }

  void _onFrame(AudioFrame frame) {
    final chunker = _chunker;
    if (chunker == null || _stopping) return;
    for (final chunk in chunker.add(pcmOf(frame))) {
      _hand(chunk);
    }
  }

  void _hand(PcmChunk chunk) {
    late final Future<void> delivery;
    delivery = sink
        .deliver(chunk)
        .catchError((Object e, StackTrace s) {
          // A chunk that never arrives costs its share of the transcript; it must
          // not take the call down with it, and it must not stall the hangup.
          Logs().w('Call audio chunk ${chunk.index} was not delivered', e, s);
        })
        .whenComplete(() => _inFlight.remove(delivery));
    _inFlight.add(delivery);
  }

  /// Stops recording, flushes the tail, and waits for delivery to settle.
  ///
  /// Idempotent, because a hangup and a disconnect can both land: the tap is
  /// cancelled and the chunker cleared before anything is awaited, so a second
  /// call has nothing left to flush and cannot emit a duplicate tail.
  Future<void> stop() async {
    final chunker = _chunker;
    if (chunker == null) return;
    _stopping = true;
    _chunker = null;

    // A tap that will not cancel must not cost the tail. The frames it may still
    // deliver are already ignored (_stopping), so the worst case is a renderer
    // left registered — losing the last seconds of what the learner said is the
    // more expensive failure.
    try {
      await _cancelTap?.call();
      _cancelTap = null;
    } catch (e, s) {
      // Kept, not discarded. A renderer that would not detach is still attached,
      // and starting again over the top of it would feed two taps into one
      // chunker — the learner's own voice counted twice.
      Logs().w('Could not cancel the call audio tap; it stays claimed', e, s);
    }

    final tail = chunker.flush();
    if (tail != null) _hand(tail);
    // Remembered before the chunker is let go, so a later stretch of the same
    // call numbers on from here.
    _nextIndex = chunker.nextIndex;

    await Future.wait(List.of(_inFlight));
    await sink.close();
  }

  /// The frame's samples as 16-bit PCM.
  ///
  /// Copies rather than views the frame's bytes: a renderer may hand back a
  /// window into a larger buffer at an odd offset, which cannot be reinterpreted
  /// as 16-bit in place, and the frame is not ours to keep past this callback.
  @visibleForTesting
  static Int16List pcmOf(AudioFrame frame) {
    final bytes = ByteData.sublistView(frame.data);
    if (frame.format == AudioFormat.Float32) {
      final out = Int16List(frame.data.lengthInBytes ~/ 4);
      for (var i = 0; i < out.length; i++) {
        final v = bytes.getFloat32(i * 4, Endian.little).clamp(-1.0, 1.0);
        out[i] = (v * 32767).round();
      }
      return out;
    }
    final out = Int16List(frame.data.lengthInBytes ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = bytes.getInt16(i * 2, Endian.little);
    }
    return out;
  }
}
