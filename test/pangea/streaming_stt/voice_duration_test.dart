import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

void main() {
  group('wavDurationMs', () {
    test('reads the length of a canonical PCM16 WAV', () {
      // 1.5 s of 16 kHz mono PCM16 = 48000 bytes.
      final wav = pcm16ToWav(Uint8List(48000));
      expect(wavDurationMs(wav), 1500);
    });

    test('honours the rate and channels in the header', () {
      // 0.25 s of 44.1 kHz stereo PCM16 = 44100 bytes.
      final wav = pcm16ToWav(Uint8List(44100), sampleRate: 44100, channels: 2);
      expect(wavDurationMs(wav), 250);
    });

    test('an unfinished header (data size 0) falls back to the bytes held', () {
      final wav = pcm16ToWav(Uint8List(32000));
      ByteData.view(wav.buffer).setUint32(40, 0, Endian.little);
      expect(wavDurationMs(wav), 1000);
    });

    test('is null for bytes that are not a WAV', () {
      expect(wavDurationMs(Uint8List.fromList([1, 2, 3])), isNull);
      expect(wavDurationMs(Uint8List(64)), isNull);
    });
  });

  group('voiceMessageDurationMs', () {
    test('keeps the length the recorder reported', () {
      expect(
        voiceMessageDurationMs(
          reported: 700,
          bytes: pcm16ToWav(Uint8List(48000)),
        ),
        700,
      );
    });

    test('computes the length from the bytes when none was reported', () {
      final wav = pcm16ToWav(Uint8List(48000));
      expect(voiceMessageDurationMs(reported: 0, bytes: wav), 1500);
      expect(voiceMessageDurationMs(reported: -1, bytes: wav), 1500);
    });

    test('stays 0 when neither the recorder nor the bytes give a length', () {
      expect(
        voiceMessageDurationMs(reported: 0, bytes: Uint8List.fromList([1, 2])),
        0,
      );
    });
  });
}
