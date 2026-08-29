import 'dart:async';
import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';
import 'package:matrix/matrix.dart' show Logs;
import 'package:pangea_call_capture/pangea_call_capture.dart';

import 'package:fluffychat/utils/platform_infos.dart';

/// Detaches a tap.
///
/// Awaitable, because a renderer's own cancel is: reporting a detach that has
/// not finished — or worse, letting its failure escape as an unhandled async
/// error — is how a tap comes to be left attached with nothing tracking it.
typedef DetachTap = FutureOr<void> Function();

/// Receives a stretch of this device's own outbound audio, and the FORMAT it
/// was captured in.
///
/// Both facts travel with the audio because neither is fixed. The audio
/// processing module picks the rate from the device and the negotiated codec
/// and changes it when either does; the channel count is reported by the
/// platform the same way, and on native it is whatever the platform decided
/// rather than what we asked for.
///
/// Requesting a format and describing one are different things, and only the
/// second one is true of the samples in hand. A channel count we assumed rather
/// than read goes into the WAV header, halves or doubles the frame count
/// derived from the byte length, and warps both the audio and every duration
/// computed from it -- without failing anywhere.
typedef CallAudioFrames =
    void Function(Int16List samples, int sampleRate, int channels);

/// Says that an attach which ALREADY ANSWERED has turned out to be dead.
///
/// Some tap points register synchronously and only then start the capture that
/// feeds them, so the failure lands after open() has handed back a detach.
/// Nothing throws and nothing is returned, so the recorder goes on holding what
/// it reads as a live recording — for the rest of the call, over a tap that will
/// never deliver a frame. This is how that silence becomes an event.
///
/// It only ever REPORTS. Letting the tap go stays the caller's, through the one
/// release path it already owns: a tap that tore itself down from in here would
/// be detached twice, and a second detach is neither guaranteed idempotent nor
/// guaranteed to answer.
typedef TapDied = void Function();

/// What livekit_client itself may spend AFTER a renderer is registered and
/// BEFORE it is in any position to deliver a frame.
///
/// `addAudioRenderer` registers synchronously and leaves the capture it starts
/// running behind it, so a watchdog armed the moment it returns is timing the
/// package's own setup and not a working tap's silence. On the web that setup
/// OPENS with `await ctx.resume().toDart.timeout(const Duration(seconds: 3))`
/// — livekit_client-2.11.0, audio_frame_capture_web.dart, whose comment says a
/// browser may reject or stall a resume until it has seen a user gesture. Only
/// afterwards does it compile the worklet module, build the graph and wire the
/// port, and the first frame is a render quantum later again.
///
/// So this is the FLOOR any first-frame budget has to clear, and it is a
/// property of the dependency rather than of a healthy attach. Named here so
/// that the relationship is the thing under test: a budget that does not exceed
/// it reports every stalled-but-recoverable browser dead.
const rendererStartupStall = Duration(seconds: 3);

/// Where a device reads its own outbound call audio from.
///
/// The tap point is the whole correctness argument for attribution: it has to
/// sit AFTER echo cancellation, or the other person's voice — coming back out of
/// the loudspeaker and into the microphone — is transcribed and credited to the
/// wrong learner. Platforms do not offer the same point, so the difference lives
/// here rather than spread through the recorder.
abstract class CallAudioTap {
  /// Attaches to [track] and begins delivering audio.
  ///
  /// Returns the function that detaches it, or null when no tap could be
  /// attached — in which case nothing is recorded. That costs the call its
  /// analytics and leaves the conversation itself untouched, which is the right
  /// way round.
  ///
  /// [onDead] carries the one answer that cannot be given by returning or
  /// throwing, because it is only known later: see [TapDied]. It is REQUIRED
  /// rather than optional because "this attach can never turn out dead" is a
  /// claim only a caller can make, and no caller of this can make it.
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  });
}

/// The WebRTC plugin's own renderer.
///
/// Correct everywhere except Android: on iOS and macOS the renderer is
/// registered inside the audio processing module, so echo cancellation has
/// already run, and on the web the browser cancels echo before it hands over a
/// track at all. The capture format is requested rather than accepted, so a
/// chunk's bytes mean the same thing on each of them.
class TrackRendererTap implements CallAudioTap {
  final int sampleRate;
  final int channels;

  /// How long a registered renderer is given to produce its first frame.
  ///
  /// Injected the way the recorder's detach timeout is, so a test need not wait
  /// it out. The number is set against [rendererStartupStall] — the cost of the
  /// SETUP this watches — rather than against the interval between frames once
  /// a capture is running. Those are different quantities and the frame
  /// interval is the wrong one: it describes a tap that already works, while
  /// every second of the wait here is spent before one exists.
  ///
  /// This was three seconds, which reads as generous by the frame interval and
  /// was in fact EQUAL to the package's resume stall on its own, with the whole
  /// worklet build still to come after it. A browser doing exactly what livekit
  /// budgets for would have had a healthy attach reported dead, and the restart
  /// would have paid the identical cost and been killed at the identical point.
  /// Fifteen seconds puts the documented setup path well inside the budget with
  /// room for a main thread that is also negotiating the call.
  ///
  /// What the wait costs is how long a genuinely dead tap goes unnoticed —
  /// bounded audio at the start of one stretch. What it buys is that the report
  /// means something. It does NOT yet buy a handover: the election ranks on
  /// device id alone, so the device that reports the death is the device that
  /// tries again, a bounded number of times. Moving the recording to a sibling
  /// needs capability ranking, which is #410 item 6 and is not here yet.
  final Duration firstFrameTimeout;

  const TrackRendererTap({
    required this.sampleRate,
    required this.channels,
    this.firstFrameTimeout = const Duration(seconds: 15),
  });

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    // The format REQUESTED below and the format the audio actually arrives in
    // are two different facts, and only the second one describes the samples.
    // On the web the renderer builds an AudioContext at the requested rate and
    // then reports whatever rate the browser really gave it -- browsers are
    // free to refuse, and the fallback is 48 kHz. Labelling 48 kHz audio as
    // 16 kHz does not fail loudly; it just transcribes as gibberish.
    //
    // The same holds for the channel count, and it used to be dropped one line
    // after this comment argued the case for the rate. On the web the renderer
    // downmixes to what we asked for, so the two agree there; on native the
    // count is read straight off the platform's own event, exactly as the rate
    // is, and nothing promises it matches the request. So the whole format that
    // travels with the audio is the frame's own, never ours.
    //
    // Registering the renderer is where this tap's own failure mode lives, and
    // it is a SILENT one. addAudioRenderer registers synchronously and starts
    // the capture that feeds it asynchronously inside livekit_client; when that
    // capture fails the package logs it and goes quiet. Nothing throws, nothing
    // is returned, and the non-null detach below reads to the recorder as a
    // live recording for the rest of the call. The watchdog under it is the
    // only thing that turns that silence back into an event.
    //
    // NULLABLE and `?.cancel()` rather than `late final`: this closure is
    // handed over BEFORE the variable is assigned, and a renderer that
    // delivered its first frame synchronously from inside addAudioRenderer
    // would read an uninitialised late field and crash the attach.
    Timer? firstFrameTimer;
    var gotFirstFrame = false;
    final cancel = track.addAudioRenderer(
      onFrame: (frame) {
        gotFirstFrame = true;
        firstFrameTimer?.cancel();
        deliver(frame, onFrames);
      },
      options: AudioRendererOptions(
        sampleRate: sampleRate,
        channels: channels,
        format: AudioFormat.Int16,
      ),
    );
    // Armed only if the synchronous case above did not already happen: arming a
    // watchdog for an event that has been and gone reports a healthy attach
    // dead the moment the frames pause.
    //
    // A mute cannot fire this falsely. call_media.dart sets
    // `stopAudioCaptureOnMute: false`, so a muted learner's track goes on
    // delivering silent frames and the recorder drops them itself; silence
    // reaching here is still a frame.
    if (!gotFirstFrame) {
      firstFrameTimer = Timer(firstFrameTimeout, () {
        Logs().w(
          'The call audio renderer attached but delivered nothing; '
          'treating the tap as dead',
        );
        // Reported, never released. Cancelling the renderer from in here would
        // detach it a second time behind the caller's own release path, which
        // is the one place a tap is ever let go.
        onDead();
      });
    }
    return () {
      // Cancelled by an ordinary teardown too. A recording short enough to stop
      // before its first frame is not a failure, and reporting one would stand
      // a healthy device aside.
      firstFrameTimer?.cancel();
      return cancel();
    };
  }

  /// What a delivered frame becomes. Named so the rate rule above can be
  /// tested without standing up a real SFU track.
  static void deliver(AudioFrame frame, CallAudioFrames onFrames) =>
      onFrames(pcmOfFrame(frame), frame.sampleRate, frame.channels);
}

/// Android's post-echo-cancellation tap.
///
/// Android's renderer attaches to the audio device module, upstream of echo
/// cancellation, so it cannot be used for anything that has to say WHO spoke.
/// This reads the audio processing module's own capture output instead.
class PostEchoCancellationTap implements CallAudioTap {
  final PangeaCallCapture capture;

  const PostEchoCancellationTap({this.capture = const PangeaCallCapture()});

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    // [onDead] goes unused here, and that is a statement rather than an
    // oversight: this platform ADJUDICATES its attach. `capture.start()` answers
    // true or false, so a tap that did not take is an answer in hand by the time
    // this method returns, and there is no window of the kind the renderer's
    // silent asynchronous start opens. A watchdog here would only be reporting
    // the far weaker "attached, then went quiet", which is not what this tap
    // does when it fails.
    //
    // Retried briefly: the processing factory is created during WebRTC's own
    // initialization, and the first call of a session can reach here moments
    // before that finishes. Two short retries cover the race; a device where
    // the tap is genuinely unavailable still answers false three times and is
    // given up on with the warning below -- each refusal is logged, so a retry
    // can never quietly paper over a real absence.
    bool attached = false;
    const delays = [Duration.zero, Duration(seconds: 1), Duration(seconds: 3)];
    for (var i = 0; i < delays.length; i++) {
      if (delays[i] != Duration.zero) await Future.delayed(delays[i]);
      try {
        attached = await capture.start();
      } catch (e, s) {
        Logs().e('Could not attach the call audio tap', e, s);
        attached = false;
      }
      if (attached) break;
      // "Retrying" only when a retry is actually coming; the final refusal is
      // the warning below, not a promise that never happens.
      if (i < delays.length - 1) {
        Logs().w('The call audio tap refused to attach; retrying');
      }
    }
    if (!attached) {
      Logs().w('No call audio tap on this device; nothing will be recorded');
      return null;
    }

    // Subscribed only AFTER the attach is owned. The frame stream is shared, so
    // a subscription taken before attach belonged to nobody -- and a stale,
    // overtaken open() sleeping in the retry above would have gone on feeding
    // the SAME onFrames pipeline beside the live recording's own listener,
    // chunking the opening seconds of the next call twice. The cost of the
    // reorder is the few frames the platform delivers between the attach
    // answer and this listen -- milliseconds -- against audio that was being
    // double-counted into a learner's analytics.
    final subscription = capture.frames.listen(
      // Mono by the capture package's own contract -- its frame carries a rate
      // precisely because that varies, and carries no channel count because
      // this does not. A literal here is the only fact available rather than an
      // assumption over one we were handed; if that package ever grows a
      // channel count, it has to travel the same way the rate does.
      (frame) => onFrames(_samplesOf(frame.pcm16), frame.sampleRate, 1),
      onError: (Object e, StackTrace s) =>
          Logs().w('The call audio tap reported an error', e, s),
    );

    // Returned rather than fired and forgotten: the caller awaits this before it
    // considers the recording stopped, and a detach that is still running is a
    // tap still attached. Discarding these also turned any failure in them into
    // an unhandled async error, which the caller's own guard could never see.
    return () async {
      // The platform side first, so nothing new is produced, and only then the
      // subscription. The other order threw away whatever had already been
      // handed over but not yet delivered — which at a hangup is the last thing
      // the learner said.
      await capture.stop();
      await subscription.cancel();
    };
  }

  /// Reads the platform's bytes as signed 16-bit samples.
  ///
  /// Read rather than viewed: the bytes arrive at whatever offset the channel
  /// gave them, and an odd offset cannot be reinterpreted as 16-bit in place.
  static Int16List _samplesOf(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    final out = Int16List(bytes.lengthInBytes ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = view.getInt16(i * 2, Endian.little);
    }
    return out;
  }
}

/// The frame's samples as 16-bit PCM.
///
/// Copies rather than views the frame's bytes: a renderer may hand back a window
/// into a larger buffer at an odd offset, which cannot be reinterpreted as
/// 16-bit in place, and the frame is not ours to keep past this callback.
Int16List pcmOfFrame(AudioFrame frame) {
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

/// The tap this platform records through.
CallAudioTap defaultCallAudioTap({
  required int sampleRate,
  required int channels,
}) => PlatformInfos.isAndroid
    ? const PostEchoCancellationTap()
    : TrackRendererTap(sampleRate: sampleRate, channels: channels);
