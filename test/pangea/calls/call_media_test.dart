import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';

/// Records what actually reached the SFU layer, so a step that runs after
/// teardown is visible rather than merely improbable.
class RecordingMedia extends CallMedia {
  final List<String> steps = [];
  bool releaseDuringConnect = false;
  bool releaseDuringMic = false;
  bool releaseDuringCamera = false;
  int disconnects = 0;

  @override
  Future<void> connectRoom(String url, String jwt) async {
    steps.add('connect');
    if (releaseDuringConnect) await disconnect();
  }

  @override
  Future<void> enableMicrophone(bool on) async {
    steps.add('mic:$on');
    if (releaseDuringMic) {
      releaseDuringMic = false;
      await disconnect();
    }
  }

  @override
  Future<void> enableCamera(bool on) async {
    steps.add('camera:$on');
    if (releaseDuringCamera) {
      releaseDuringCamera = false;
      await disconnect();
    }
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    steps.add('disconnect');
    await super.disconnect();
  }
}

void main() {
  const grant = CallToken(jwt: 'jwt', url: 'ws://sfu');

  test('connects, then publishes audio, then video', () async {
    final media = RecordingMedia();
    await media.connect(grant, video: true);
    expect(media.steps, ['connect', 'mic:true', 'camera:true']);
  });

  test('a voice call publishes no camera', () async {
    final media = RecordingMedia();
    await media.connect(grant, video: false);
    expect(media.steps, ['connect', 'mic:true']);
  });

  test('a hangup landing mid-connect stops the microphone opening', () async {
    // Connecting is several round-trips and a hangup can land inside any of
    // them. Without a check between steps the call would open a microphone,
    // and a camera, after teardown had already run.
    final media = RecordingMedia()..releaseDuringConnect = true;
    await media.connect(grant, video: true);

    expect(media.steps, ['connect', 'disconnect', 'disconnect']);
    expect(
      media.steps,
      isNot(contains('mic:true')),
      reason: 'a call the user abandoned must not open capture devices',
    );
  });

  test(
    'a hangup landing WHILE the microphone opens still releases it',
    () async {
      // The check before each step cannot stop a step already in flight. The
      // microphone opens anyway, so returning without releasing would leave it
      // open with nothing left to close it.
      final media = RecordingMedia()..releaseDuringMic = true;
      await media.connect(grant, video: true);

      expect(media.steps, ['connect', 'mic:true', 'disconnect', 'disconnect']);
      expect(
        media.steps,
        isNot(contains('camera:true')),
        reason: 'and nothing further is opened',
      );
    },
  );

  test('a hangup landing WHILE the camera opens still releases it', () async {
    final media = RecordingMedia()..releaseDuringCamera = true;
    await media.connect(grant, video: true);

    expect(media.steps.last, 'disconnect');
    expect(media.disconnects, 2, reason: 'the reconcile runs after the step');
  });

  test('connect after release does nothing at all', () async {
    final media = RecordingMedia();
    await media.disconnect();
    media.steps.clear();
    await media.connect(grant, video: true);
    expect(media.steps, isEmpty);
  });

  group('turning a device on mid-call obeys the same rule as coming up', () {
    test('unmuting into a call that has already ended opens nothing', () async {
      // The user taps unmute at the same moment the other side hangs up. The
      // microphone must not come back on for a call that is over — the same
      // leak the checks in connect() exist to prevent, on the toggle path.
      final media = RecordingMedia();
      await media.disconnect();
      media.steps.clear();
      await media.setMicrophoneEnabled(true);
      expect(
        media.steps,
        isNot(contains('mic:true')),
        reason: 'an ended call must not reopen the microphone',
      );
    });

    test('an unmute racing a hangup releases the microphone it opened', () async {
      // The check before cannot stop an enable already in flight. It opens the
      // microphone anyway, so it must reconcile afterwards rather than leave it
      // open with nothing left to close it.
      final media = RecordingMedia()..releaseDuringMic = true;
      await media.setMicrophoneEnabled(true);
      expect(media.steps, ['mic:true', 'disconnect', 'disconnect']);
    });

    test('muting an ended call is a harmless no-op, never guarded', () async {
      // Turning a device OFF only releases it, so it is always allowed — a mute
      // after the call ended must still be attempted, not refused.
      final media = RecordingMedia();
      await media.disconnect();
      media.steps.clear();
      await media.setMicrophoneEnabled(false);
      expect(media.steps, ['mic:false']);
    });
  });
}
