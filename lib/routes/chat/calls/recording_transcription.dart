/// Turns a whole call recording into transcript segments, in a caller-specified
/// language pair, without a recorder, a call, or a homeserver.
///
/// This is the shared core of `CallAudioRecorder`'s own-recording transcription,
/// lifted out so a SECOND caller -- the whole-call transcriber (#8792), which
/// transcribes the OTHER participant's saved recording after downloading it --
/// runs exactly the same chunking, downsampling, and word-timing merge over
/// arbitrary bytes and languages. The recorder still owns the run lifecycle and
/// delegates the STT here; nothing about its own path changed, and
/// [transcribeRecordingPcm]'s tests are the recorder's own end-to-end ones.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/audio_encoding_enum.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart'
    show ChunkTranscriber;
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart'
    show SpeechToTextResponseModel, WordTiming;

/// The rate the STT copy of a recording is downsampled to. 16 kHz mono is what
/// speech-to-text providers accept natively (see `captureSampleRate` in
/// call_capture.dart) and keeps the request under the choreographer's cap.
const kSttSampleRate = 16000;

/// The most PCM one STT piece may carry. Its WAV (this + a 44-byte header) must
/// base64-encode under the choreographer's 10 MB (10485760 byte) audio_content
/// cap; base64 inflates by 4/3, so the raw ceiling is ~7.86 MB and this leaves
/// margin for the header and rounding. A recording longer than one piece
/// (~3.6 min at 16 kHz mono) is transcribed in several and merged, so there is
/// no whole-recording length limit. Frame alignment is applied at use.
const kMaxSttPieceBytes = 7000000;

/// Transcribes LINEAR16 PCM16 [pcm] (at [sampleRate]/[channels]) into recording
/// segments placed on [startedAtMs] .. [startedAtMs] + [durationMs].
///
/// Non-fatal by contract, exactly as the recorder's own path was: an STT
/// failure, an over-length piece with no timings, or an empty result all yield
/// an empty list, and this never throws. The STT copy is downsampled to
/// [kSttSampleRate] for mono audio (STT gains nothing above it and a native-rate
/// phone recording blows the request cap); the caller's own bytes are never
/// mutated. A call longer than one [maxSttPieceBytes] piece is transcribed in
/// cap-sized pieces whose word timings are offset onto ONE recording timeline
/// and merged.
Future<List<TranscriptSegment>> transcribeRecordingPcm(
  Uint8List pcm, {
  required int startedAtMs,
  required int sampleRate,
  required int channels,
  required int durationMs,
  required ChunkTranscriber transcribe,
  required String l1,
  required String l2,
  int maxSttPieceBytes = kMaxSttPieceBytes,

  /// Checked before each piece is sent. True means the caller's time for the
  /// recording-based half is spent: the result is an empty list -- never a
  /// partial half -- and the live half stands.
  bool Function()? overBudget,
}) async {
  try {
    // Downsample only the STT copy, and only for mono (every recording here is
    // mono; a box-average over interleaved stereo would mix the channels).
    var sttPcm = pcm;
    var sttRate = sampleRate;
    if (channels == 1 && sampleRate > kSttSampleRate) {
      sttPcm = _downsamplePcm16Mono(pcm, sampleRate, kSttSampleRate);
      sttRate = kSttSampleRate;
    }

    Future<SpeechToTextResponseModel> transcribePiece(Uint8List piecePcm) {
      return transcribe(
        SpeechToTextRequestModel(
          audioContent: pcm16ToWav(
            piecePcm,
            sampleRate: sttRate,
            channels: channels,
          ),
          includeWordTimings: true,
          config: SpeechToTextAudioConfigModel(
            encoding: AudioEncodingEnum.linear16,
            sampleRateHertz: sttRate,
            userL1: l1,
            userL2: l2,
          ),
        ),
      );
    }

    // Cap each piece so its WAV's base64 body stays under the choreographer's
    // 10 MB limit; a piece must not split a frame (channels*2 bytes), and must
    // be at least one frame so the piece arithmetic below can never divide by
    // zero (a cap smaller than a frame is only reachable via a test override).
    final frame = channels * 2;
    final maxPieceBytes = max(
      frame,
      maxSttPieceBytes - (maxSttPieceBytes % frame),
    );
    final pieceCount = (sttPcm.length + maxPieceBytes - 1) ~/ maxPieceBytes;

    // The common case -- a call short enough for one request -- takes the
    // single-response path unchanged, including its no-word-timings fallback.
    if (pieceCount <= 1) {
      if (overBudget?.call() ?? false) {
        Logs().i('Recording-based call transcription skipped: over budget');
        return const [];
      }
      return buildRecordingSegments(
        await transcribePiece(sttPcm),
        startedAtMs,
        durationMs,
      );
    }

    // A long call: transcribe it in cap-sized pieces and merge their word
    // timings onto ONE recording timeline. Deterministic over the complete
    // recording -- every piece is present, so nothing is dropped the way a live
    // 45 s chunk can be. A piece with a usable transcript but no timings cannot
    // be placed, so it abandons the whole recording-based attempt (the live
    // half, or the server backstop, then stands) rather than emit a partial
    // half.
    final merged = <WordTiming>[];
    final texts = <String>[];
    final msPerByte = 1000 / (sttRate * frame);
    for (var offset = 0; offset < sttPcm.length; offset += maxPieceBytes) {
      final end = offset + maxPieceBytes < sttPcm.length
          ? offset + maxPieceBytes
          : sttPcm.length;
      final pieceStartMs = (offset * msPerByte).round();
      final pieceDurationMs = ((end - offset) * msPerByte).round();
      if (overBudget?.call() ?? false) {
        Logs().i(
          'Recording-based call transcription stopped over budget; the live '
          'transcript stands',
        );
        return const [];
      }
      final response = await transcribePiece(
        Uint8List.sublistView(sttPcm, offset, end),
      );
      // A piece the provider read as silence contributes no words -- a real
      // quiet stretch, not a loss.
      if (!response.hasUsableTranscript) continue;
      final transcript = response.transcript;
      final timings = transcript.wordTimings;
      if (timings == null || timings.isEmpty) return const [];
      // A timing is kept only when it lies within THIS piece's own
      // [0, pieceDurationMs], mirroring how the single-response path bounds to
      // the whole recording. An out-of-piece value (a negative or overlong
      // provider timestamp) becomes null so its word is floor-placed, never a
      // spurious in-range absolute time that the offset would otherwise sneak
      // past the whole-recording bound.
      int? shift(int? at) => (at == null || at < 0 || at > pieceDurationMs)
          ? null
          : at + pieceStartMs;
      for (final w in timings) {
        merged.add(
          WordTiming(
            word: w.word,
            confidence: w.confidence,
            startTimeMs: shift(w.startTimeMs),
            endTimeMs: shift(w.endTimeMs),
          ),
        );
      }
      texts.add(transcript.text);
    }
    return buildRecordingSegmentsFromTimings(
      merged,
      texts.join(' '),
      startedAtMs,
      durationMs,
    );
  } catch (e, s) {
    Logs().w(
      'Recording-based call transcription failed; the live transcript stands',
      e,
      s,
    );
    return const [];
  }
}

/// Transcribes a whole-call recording delivered as WAV [bytes] (this app's own
/// `pcm16ToWav` output, or any PCM16 RIFF/WAVE), in the [l1]/[l2] pair.
///
/// The whole-call transcriber downloads a peer's saved `pangea.call_audio` blob,
/// which is a PCM16 WAV, and hands it here: the PCM samples and their sample
/// rate are read out of the container and passed to [transcribeRecordingPcm], so
/// the same chunking and downsampling run over a peer's recording as over the
/// device's own. Non-fatal like [transcribeRecordingPcm]: bytes that are not a
/// readable PCM16 WAV yield an empty list rather than an exception.
Future<List<TranscriptSegment>> transcribeRecordingWav(
  Uint8List bytes, {
  required int startedAtMs,
  required int durationMs,
  required ChunkTranscriber transcribe,
  required String l1,
  required String l2,
  int maxSttPieceBytes = kMaxSttPieceBytes,
}) async {
  final parsed = pcmFromWav(bytes);
  if (parsed == null) {
    Logs().w(
      'A call recording could not be read as PCM16 WAV; not transcribed',
    );
    return const [];
  }
  return transcribeRecordingPcm(
    parsed.pcm,
    startedAtMs: startedAtMs,
    sampleRate: parsed.sampleRate,
    channels: parsed.channels,
    durationMs: durationMs,
    transcribe: transcribe,
    l1: l1,
    l2: l2,
    maxSttPieceBytes: maxSttPieceBytes,
  );
}

/// The little-endian PCM16 samples of a RIFF/WAVE container, with their sample
/// rate and channel count, or null when [bytes] is not a readable PCM16 WAV.
///
/// Walks the RIFF chunk list rather than assuming a fixed 44-byte header, so a
/// foreign layout (a `fmt ` chunk with extra bytes, chunks in an unusual order,
/// a trailing chunk after `data`) is handled; this app's own `pcm16ToWav` output
/// is the canonical case. Returns the PCM as a byte view -- little-endian PCM16,
/// the same shape `pcm16ToWav` consumes -- so [transcribeRecordingPcm] reads it
/// with the explicit-endian downsampler rather than a host-endian `Int16List`.
({Uint8List pcm, int sampleRate, int channels})? pcmFromWav(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final data = ByteData.sublistView(bytes);
  if (!_tagEquals(bytes, 0, 'RIFF') || !_tagEquals(bytes, 8, 'WAVE')) {
    return null;
  }

  // Bound the chunk walk by the declared RIFF payload so trailing bytes past the
  // container are never parsed as chunks; fall back to the buffer length when
  // the declared size is implausible or overruns, and never read past the
  // buffer either way.
  final declaredRiff = data.getUint32(4, Endian.little);
  final riffEnd = (declaredRiff >= 4 && 8 + declaredRiff <= bytes.length)
      ? 8 + declaredRiff
      : bytes.length;

  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLen;

  var offset = 12;
  while (offset + 8 <= riffEnd) {
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final bodyStart = offset + 8;
    if (_tagEquals(bytes, offset, 'fmt ')) {
      if (chunkSize >= 16 && bodyStart + 16 <= riffEnd) {
        audioFormat = data.getUint16(bodyStart, Endian.little);
        channels = data.getUint16(bodyStart + 2, Endian.little);
        sampleRate = data.getUint32(bodyStart + 4, Endian.little);
        bitsPerSample = data.getUint16(bodyStart + 14, Endian.little);
      }
    } else if (_tagEquals(bytes, offset, 'data')) {
      dataOffset = bodyStart;
      // Clamp a data chunk that overruns the container to what is present, so a
      // truncated blob yields the samples it has and never an out-of-range read.
      final available = riffEnd - bodyStart;
      dataLen = chunkSize <= available ? chunkSize : available;
    }
    // Chunks are word-aligned: an odd body is padded to even.
    var advance = chunkSize;
    if (advance.isOdd) advance += 1;
    offset = bodyStart + advance;
  }

  if (audioFormat != 1 || bitsPerSample != 16) return null;
  if (channels == null || channels <= 0) return null;
  if (sampleRate == null || sampleRate <= 0) return null;
  if (dataOffset == null || dataLen == null || dataLen <= 0) return null;

  // A frame-aligned view of the PCM body: full sample frames only, so a blob
  // whose data chunk ends mid-frame contributes only its whole frames.
  final frame = channels * 2;
  final usableLen = dataLen - (dataLen % frame);
  if (usableLen <= 0) return null;
  return (
    pcm: Uint8List.sublistView(bytes, dataOffset, dataOffset + usableLen),
    sampleRate: sampleRate,
    channels: channels,
  );
}

bool _tagEquals(Uint8List bytes, int offset, String tag) {
  if (offset + tag.length > bytes.length) return false;
  for (var i = 0; i < tag.length; i++) {
    if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
  }
  return true;
}

/// Downsamples mono PCM16 [pcm] from [fromRate] to [toRate] by averaging each
/// output sample's span of input samples -- a box-filter decimation that
/// low-passes as it resamples, so it does not alias the way naive
/// sample-dropping would. Adequate for speech STT (not a mastering-grade
/// resampler). Reads every sample with an explicit little-endian
/// [ByteData.getInt16] rather than an `Int16List` view, whose endianness is the
/// host's and breaks on the web. Returns [pcm] unchanged when [fromRate] <=
/// [toRate].
Uint8List _downsamplePcm16Mono(Uint8List pcm, int fromRate, int toRate) {
  if (fromRate <= toRate) return pcm;
  final input = ByteData.sublistView(pcm);
  final inLen = pcm.lengthInBytes ~/ 2;
  final outLen = (inLen * toRate) ~/ fromRate;
  final out = Uint8List(outLen * 2);
  final outView = ByteData.sublistView(out);
  for (var j = 0; j < outLen; j++) {
    final start = (j * fromRate) ~/ toRate;
    var end = ((j + 1) * fromRate) ~/ toRate;
    if (end <= start) end = start + 1;
    if (end > inLen) end = inLen;
    var sum = 0;
    for (var i = start; i < end; i++) {
      sum += input.getInt16(i * 2, Endian.little);
    }
    outView.setInt16(j * 2, sum ~/ (end - start), Endian.little);
  }
  return out;
}
