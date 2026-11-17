import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:fluffychat/routes/chat/recording_view_model.dart';

void main() {
  group('voiceRecordingEncoder (#9852)', () {
    test('web records raw PCM, not record_web WAV', () {
      // record_web's WAV encoder re-copies the whole recording on every audio
      // chunk, which froze the tab near a minute. Web records PCM and adds the
      // WAV header once at stop.
      expect(voiceRecordingEncoder(isWeb: true), AudioEncoder.pcm16bits);
    });

    test('native keeps WAV', () {
      expect(voiceRecordingEncoder(isWeb: false), AudioEncoder.wav);
    });
  });
}
