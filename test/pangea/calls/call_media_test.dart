import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';

/// Records what actually reached the SFU layer, so a step that runs after
/// teardown is visible rather than merely improbable.
class RecordingMedia extends CallMedia {
  final List<String> steps = [];
  bool releaseDuringConnect = false;

  @override
  Future<void> connectRoom(String url, String jwt) async {
    steps.add('connect');
    if (releaseDuringConnect) await disconnect();
  }

  @override
  Future<void> enableMicrophone(bool on) async => steps.add('mic:$on');

  @override
  Future<void> enableCamera(bool on) async => steps.add('camera:$on');
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

    expect(media.steps, ['connect']);
    expect(
      media.steps,
      isNot(contains('mic:true')),
      reason: 'a call the user abandoned must not open capture devices',
    );
  });

  test('connect after release does nothing at all', () async {
    final media = RecordingMedia();
    await media.disconnect();
    await media.connect(grant, video: true);
    expect(media.steps, isEmpty);
  });
}
