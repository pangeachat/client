import 'dart:typed_data';

/// Synthesize a valid PCM16 WAV byte stream from raw little-endian PCM16
/// samples (D5a "retained WAV").
///
/// The streaming path replaces the current `AudioEncoder.wav` file recorder with
/// a single PCM16 mic stream (see [SttAudioCapture]); the accumulated bytes are
/// wrapped here with the canonical 44-byte PCM header so the sent `m.audio` is a
/// normal, playable WAV identical in shape to today's recorder output — no
/// second recorder, no re-encode.
///
/// Header layout (all multi-byte fields little-endian):
/// ```
///  0 RIFF            12 fmt             36 data
///  4 ChunkSize       16 Subchunk1Size   40 Subchunk2Size (== data length)
///  8 WAVE            20 AudioFormat=1    44 <pcm bytes...>
///                    22 NumChannels
///                    24 SampleRate
///                    28 ByteRate
///                    32 BlockAlign
///                    34 BitsPerSample=16
/// ```
Uint8List pcm16ToWav(
  Uint8List pcm, {
  int sampleRate = 16000,
  int channels = 1,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final dataLen = pcm.length;

  final out = Uint8List(44 + dataLen);
  final view = ByteData.view(out.buffer);

  void ascii(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      out[offset + i] = tag.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataLen, Endian.little); // ChunkSize
  ascii(8, 'WAVE');

  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM)
  view.setUint16(20, 1, Endian.little); // AudioFormat == 1 (PCM)
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);

  ascii(36, 'data');
  view.setUint32(40, dataLen, Endian.little); // Subchunk2Size

  out.setRange(44, 44 + dataLen, pcm);
  return out;
}

/// The length of a PCM WAV in milliseconds, read from its own header, or null
/// when [bytes] are not a WAV this can read.
///
/// Walks the RIFF chunks for `fmt ` (byte rate) and `data` (sample bytes). A
/// recorder stopped before it finalised its header leaves the data size 0 or
/// larger than the file; then the bytes actually held after the header are the
/// sample data.
int? wavDurationMs(Uint8List bytes) {
  String tag(int offset) => String.fromCharCodes(bytes, offset, offset + 4);
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  final view = ByteData.sublistView(bytes);
  int? byteRate;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      byteRate = view.getUint32(body + 8, Endian.little);
    } else if (id == 'data') {
      if (byteRate == null || byteRate <= 0) return null;
      final held = bytes.length - body;
      final dataLen = size == 0 || size > held ? held : size;
      return dataLen * 1000 ~/ byteRate;
    }
    // Chunks are word-aligned: an odd size carries one pad byte.
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

/// The length a voice message is sent and reported with: the recorder's own
/// [reported] milliseconds when it gave one, else the length of the recorded
/// [bytes] (every recorder path sends a WAV). 0 only when neither gives one.
int voiceMessageDurationMs({required int reported, required Uint8List bytes}) {
  if (reported > 0) return reported;
  return wavDurationMs(bytes) ?? 0;
}
