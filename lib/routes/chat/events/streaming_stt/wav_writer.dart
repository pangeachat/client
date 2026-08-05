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
