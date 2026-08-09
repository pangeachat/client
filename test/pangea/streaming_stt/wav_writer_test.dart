import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

/// Little-endian readers so the assertions read header fields exactly as a
/// WAV decoder would, rather than trusting the writer's own byte math.
int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
String _ascii(Uint8List b, int o, int len) =>
    String.fromCharCodes(b.sublist(o, o + len));

void main() {
  group('pcm16ToWav header (D5a canonical 44-byte PCM16 header)', () {
    // 8 PCM16 samples = 16 bytes of data.
    final pcm = Uint8List.fromList(<int>[
      0, 0, //
      255, 127, // 0x7FFF max positive
      0, 128, // 0x8000 max negative
      1, 0, //
      2, 0, //
      3, 0, //
      4, 0, //
      5, 0, //
    ]);

    test('total length == 44-byte header + pcm length', () {
      final wav = pcm16ToWav(pcm);
      expect(wav.length, 44 + pcm.length);
    });

    test(
      'RIFF / WAVE / fmt / data chunk ids are present at the right offsets',
      () {
        final wav = pcm16ToWav(pcm);
        expect(_ascii(wav, 0, 4), 'RIFF');
        expect(_ascii(wav, 8, 4), 'WAVE');
        expect(_ascii(wav, 12, 4), 'fmt ');
        expect(_ascii(wav, 36, 4), 'data');
      },
    );

    test('RIFF ChunkSize == 36 + dataLen', () {
      final wav = pcm16ToWav(pcm);
      expect(_u32(wav, 4), 36 + pcm.length);
    });

    test('fmt subchunk describes PCM 16-bit / 16000Hz / mono', () {
      final wav = pcm16ToWav(pcm);
      expect(_u32(wav, 16), 16); // Subchunk1Size (PCM)
      expect(_u16(wav, 20), 1); // AudioFormat == 1 (PCM)
      expect(_u16(wav, 22), 1); // NumChannels == mono
      expect(_u32(wav, 24), 16000); // SampleRate
      expect(_u32(wav, 28), 16000 * 1 * 2); // ByteRate
      expect(_u16(wav, 32), 1 * 2); // BlockAlign
      expect(_u16(wav, 34), 16); // BitsPerSample
    });

    test(
      'data Subchunk2Size == pcm length, and the pcm bytes follow verbatim',
      () {
        final wav = pcm16ToWav(pcm);
        expect(_u32(wav, 40), pcm.length);
        expect(wav.sublist(44), equals(pcm));
      },
    );

    test('honours a non-default sample rate / channel count in the header', () {
      final wav = pcm16ToWav(pcm, sampleRate: 8000, channels: 2);
      expect(_u16(wav, 22), 2);
      expect(_u32(wav, 24), 8000);
      expect(_u32(wav, 28), 8000 * 2 * 2);
      expect(_u16(wav, 32), 2 * 2);
    });

    test('empty pcm yields a valid header-only WAV (data length 0)', () {
      final wav = pcm16ToWav(Uint8List(0));
      expect(wav.length, 44);
      expect(_u32(wav, 4), 36);
      expect(_u32(wav, 40), 0);
    });
  });

  group('WAV round-trips through a real temp file (readable on disk)', () {
    test(
      'written bytes read back byte-identical with a decodable header',
      () async {
        final pcm = Uint8List.fromList(List<int>.generate(320, (i) => i % 256));
        final wav = pcm16ToWav(pcm);

        final dir = await Directory.systemTemp.createTemp('wav_writer_test');
        final file = File('${dir.path}/out.wav');
        await file.writeAsBytes(wav);

        final readBack = await file.readAsBytes();
        expect(readBack, equals(wav));
        expect(_ascii(readBack, 0, 4), 'RIFF');
        expect(_u32(readBack, 40), pcm.length);

        await dir.delete(recursive: true);
      },
    );
  });
}
