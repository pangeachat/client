import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/calls/speech_trim.dart';

/// A real 40.4s call chunk: roughly 22s of this device's own noise floor while
/// the other person talked, then roughly 18s of speech.
///
/// The recording is the whole point of this file. Sent whole to Deepgram it
/// returned THREE words; its 22.3-40.2s span returned FORTY-SEVEN, correctly.
/// Local Whisper fails the same way, reading all of 0-22s as one fabricated
/// "Hey." — so the defect belongs to the AUDIO, not to a provider, and a
/// detector is only worth anything if it can find the speech in this file.
const _fixture = 'test/pangea/calls/fixtures/call_noise_then_speech.wav';

/// Where the speech actually is, measured by transcribing the spans one by one.
const _speechStartMs = 22300;
const _fileEndMs = 40400;

Int16List _loadFixture() {
  final bytes = File(_fixture).readAsBytesSync();
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  // Walk the RIFF chunks rather than assuming a 44-byte header: a writer is
  // free to put LIST or fact chunks in front of the samples, and reading those
  // as audio would make every assertion below meaningless.
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      final pcm = bytes.sublist(
        offset + 8,
        min(offset + 8 + size, bytes.length),
      );
      return Int16List.view(Uint8List.fromList(pcm).buffer, 0, pcm.length ~/ 2);
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('no data chunk in $_fixture');
}

PcmChunk _chunk(
  Int16List samples, {
  int sampleRate = 16000,
  int channels = 1,
  int index = 0,
  int startedAtMs = 1000,
}) => PcmChunk(
  pcm: Uint8List.view(
    samples.buffer,
    samples.offsetInBytes,
    samples.lengthInBytes,
  ),
  sampleRate: sampleRate,
  channels: channels,
  index: index,
  startedAtMs: startedAtMs,
);

/// The same signal on two channels, the second inverted.
///
/// Clamped at the negative floor: -32768 has no positive counterpart in 16 bits
/// and negating it wraps back to itself, which would leave the two channels
/// identical exactly where the test needs them opposed.
Int16List _antiPhase(Int16List mono) {
  final out = Int16List(mono.length * 2);
  for (var i = 0; i < mono.length; i++) {
    out[i * 2] = mono[i];
    out[i * 2 + 1] = mono[i] == -32768 ? 32767 : -mono[i];
  }
  return out;
}

Int16List _range(Int16List all, double fromSec, double toSec) =>
    Int16List.sublistView(
      all,
      (fromSec * 16000).round(),
      (toSec * 16000).round(),
    );

void main() {
  late Int16List audio;

  setUpAll(() {
    audio = _loadFixture();
  });

  group('the real recording', () {
    test('finds the speech and leaves the noise behind', () {
      final trimmed = trimToSpeech(_chunk(audio));

      expect(trimmed, isNotNull, reason: 'the chunk plainly contains speech');
      // The speech starts at 22.3s. The span may open a little early — padding
      // and the smoothing window both reach backwards — but it must not open
      // anywhere near the front of the file, which is what sending the whole
      // chunk does today.
      expect(
        trimmed!.startMs,
        inInclusiveRange(19000, _speechStartMs + 500),
        reason: 'must skip the noise without clipping the first word',
      );
      // Speech runs to the end of the file, so the span has to reach it.
      expect(
        trimmed.startMs + trimmed.durationMs,
        greaterThan(_fileEndMs - 700),
      );
      // Less than 60% of the file survives; the whole point is sending less.
      expect(trimmed.durationMs, lessThan(0.6 * _fileEndMs));
    });

    test('the noise on its own is captured but silent', () {
      // Deepgram returned 0 words for 10.2-13.6s and four words of repeated
      // hallucination for 15.9-17.9s; Whisper returned nothing for every span
      // in here. Sending it can only invent words, so it is not sent.
      expect(trimToSpeech(_chunk(_range(audio, 0, 22))), isNull);
      expect(trimToSpeech(_chunk(_range(audio, 0, 10))), isNull);
      expect(trimToSpeech(_chunk(_range(audio, 10, 22))), isNull);
    });

    test('a trim that saves little is refused, and the whole chunk sent', () {
      // Three seconds of noise in front of the speech: a span covering ~85% of
      // the chunk. Trimming that buys almost nothing and carries all of the
      // clipping risk, so the whole chunk goes instead.
      //
      // The margin is what makes this test bite. Measured against the speech
      // region ALONE the span covers ~100%, and a slice of a 100% span is
      // indistinguishable from the whole chunk -- so that version of this test
      // passed with the rule deleted.
      final mostlySpeech = Int16List.fromList([
        ..._range(audio, 19.3, 22.3),
        ..._range(audio, 22.3, 40.2),
      ]);
      final trimmed = trimToSpeech(_chunk(mostlySpeech));

      expect(trimmed, isNotNull);
      expect(trimmed!.startMs, 0, reason: 'the whole chunk, not a slice of it');
      expect(trimmed.durationMs, closeTo(20900, 60));
    });
  });

  group('what must never be dropped', () {
    test('a short chunk is sent whole and never analysed', () {
      // The defect needs a lot of noise to swamp a little speech, so a short
      // chunk cannot suffer from it -- and this is where a one-word answer
      // lives.
      //
      // The audio is deliberately the QUIET noise this detector suppresses on
      // sight: analysed, it would come back silent, and only the short-circuit
      // sends it. An earlier version of this test used a louder stretch that
      // survived analysis anyway, so it passed whether or not the rule existed.
      final short = _range(audio, 0, 7.9);
      expect(
        trimToSpeech(_chunk(short, index: 1)),
        isNotNull,
        reason: 'short audio is sent whatever the detector thinks of it',
      );

      final trimmed = trimToSpeech(_chunk(short))!;
      expect(trimmed.startMs, 0);
      expect(trimmed.durationMs, closeTo(7900, 60));

      // The same audio, one second longer, is past the floor and suppressed --
      // which is what shows the short-circuit is doing the work above.
      expect(trimToSpeech(_chunk(_range(audio, 0, 9))), isNull);
    });

    test('a short answer buried in noise is found', () {
      // 350ms of real speech dropped into eight seconds of this recording's own
      // noise. "haan", "nahi", "yes" and "okay" are exactly the credit-bearing
      // utterances a learner produces, and a design that only recognised
      // sustained conversation would lose every one of them.
      final builder = <int>[
        ..._range(audio, 4.0, 8.0),
        ..._range(audio, 29.0, 29.35),
        ..._range(audio, 8.0, 12.0),
      ];
      final trimmed = trimToSpeech(_chunk(Int16List.fromList(builder)));

      expect(trimmed, isNotNull, reason: 'a short answer is still an answer');
      expect(trimmed!.startMs, inInclusiveRange(3400, 4100));
      expect(trimmed.durationMs, lessThan(2000));
    });

    test('loud but aperiodic audio is sent rather than suppressed', () {
      // Audio we do not UNDERSTAND is not audio we know to be empty: whispered
      // and wholly unvoiced speech carry level without periodicity. Here the
      // speech region keeps its envelope and loses its pitch.
      final speech = _range(audio, 22.3, 40.2);
      final random = Random(7);
      final scrambled = Int16List(speech.length);
      for (var i = 0; i < speech.length; i++) {
        scrambled[i] = random.nextBool() ? speech[i] : -speech[i];
      }

      expect(
        trimToSpeech(_chunk(scrambled)),
        isNotNull,
        reason: 'aperiodic does not mean empty',
      );
    });

    test('unvoiced speech is kept even when noise outweighs it', () {
      // The shape this whole file exists for, with the speech half whispered:
      // 22s of room noise then 18s of wholly aperiodic speech. There is no
      // periodicity to find anywhere in it, so the level veto is all that
      // stands between eighteen seconds of somebody talking and the bin.
      //
      // It has to be the LOUDEST STRETCH rather than the chunk average. Averaged,
      // this chunk scores 0.58 against pure noise's 0.46 -- twelve points apart,
      // and on the wrong side of any thereshold that still suppressed the noise.
      // Over the loudest three seconds the same two score 0.99 and 0.72.
      final random = Random(5);
      final speech = _range(audio, 22.3, 40.2);
      final whispered = Int16List(speech.length);
      for (var i = 0; i < speech.length; i++) {
        whispered[i] = random.nextBool() ? speech[i] : -speech[i];
      }
      final chunk = Int16List.fromList([..._range(audio, 0, 22), ...whispered]);

      expect(
        trimToSpeech(_chunk(chunk)),
        isNotNull,
        reason: 'eighteen seconds of speech is not silence',
      );
      // And the noise it is buried in, alone, is still suppressed -- otherwise
      // the veto would simply have stopped working.
      expect(trimToSpeech(_chunk(_range(audio, 0, 22))), isNull);
    });

    test('opposite-phase channels still have their speech FOUND', () {
      // A signed downmix is the obvious way to make one signal out of several,
      // and it is the wrong one: two channels in opposite phase sum to nothing.
      //
      // Asserted on the TRIM rather than merely on not-being-suppressed. The
      // level veto sums energy across channels and would rescue this chunk
      // whole even if the voicing test had been handed silence -- so only an
      // assertion that the speech was actually LOCATED can tell the two apart.
      final antiPhase = _antiPhase(_range(audio, 0, 40.4));
      final trimmed = trimToSpeech(_chunk(antiPhase, channels: 2));

      expect(trimmed, isNotNull);
      expect(
        trimmed!.startMs,
        inInclusiveRange(19000, _speechStartMs + 500),
        reason: 'cancelled audio would find no speech and send everything',
      );
    });

    test('opposite-phase channels are not read as a quiet chunk', () {
      // The other half of the same mistake, isolated. Here there is no
      // periodicity for the voicing test to find whichever channel it reads,
      // so the level veto is the only thing standing between the chunk and the
      // bin -- and a veto that squared the MEAN of the channels would measure
      // this as digital silence.
      final speech = _range(audio, 22.3, 40.2);
      final random = Random(13);
      final whispered = Int16List(speech.length);
      for (var i = 0; i < speech.length; i++) {
        whispered[i] = random.nextBool() ? speech[i] : -speech[i];
      }

      expect(
        trimToSpeech(_chunk(_antiPhase(whispered), channels: 2)),
        isNotNull,
        reason: 'summed energy sees it; a signed mean cancels it away',
      );
    });

    test('the level that vetoes suppression is read across all channels', () {
      // A speaker recorded onto ONE side: silent left, loud aperiodic right.
      // The veto has to see the audio that exists, so it has to downmix rather
      // than sample whichever channel comes first. Reading channel zero alone
      // finds digital silence here and throws away a whole side of somebody
      // talking -- and with identical channels the two are indistinguishable,
      // which is why this case has them differ.
      final speech = _range(audio, 22.3, 40.2);
      final random = Random(11);
      final stereo = Int16List(speech.length * 2);
      for (var i = 0; i < speech.length; i++) {
        stereo[i * 2] = 0;
        stereo[i * 2 + 1] = random.nextBool() ? speech[i] : -speech[i];
      }

      expect(
        trimToSpeech(_chunk(stereo, channels: 2)),
        isNotNull,
        reason: 'the right channel is full of somebody talking',
      );
    });
  });

  group('what this detector cannot do', () {
    test('a short unvoiced answer in a long quiet chunk is held back', () {
      // A KNOWN LIMIT, pinned so it is visible rather than discovered.
      //
      // 350ms of wholly unvoiced speech in eight seconds of quiet has no
      // periodicity to find, and it is far too little audio to move the level
      // veto -- so it is suppressed.
      //
      // The obvious repair is to veto suppression on a RUN of loud windows
      // rather than a fraction of them, and it cannot be taken. Measured on
      // this recording's non-speech stretch: thirteen loud runs of 200ms or
      // more, the longest 960ms -- LONGER and LOUDER than the whispered answer
      // being protected. That rule would refuse to suppress the exact audio
      // this file exists to stop sending, which transcribes to nothing on both
      // providers and to invented words on each.
      //
      // Energy cannot separate the two cases. Separating them needs spectral
      // structure, and there is no whispered sample here to calibrate it on;
      // guessing would be the third time this investigation tuned against a
      // recording it did not have.
      final quiet = _range(audio, 0, 4);
      final vowel = _range(audio, 29.0, 29.35);
      final unvoiced = Int16List(vowel.length);
      final random = Random(3);
      for (var i = 0; i < vowel.length; i++) {
        unvoiced[i] = random.nextBool() ? vowel[i] : -vowel[i];
      }
      final chunk = Int16List.fromList([
        ...quiet,
        ...unvoiced,
        ..._range(audio, 4, 8),
      ]);

      expect(
        trimToSpeech(_chunk(chunk)),
        isNull,
        reason: 'documented gap: see the design doc, Known gaps',
      );

      // What DOES protect it: the same answer one chunk shorter is under the
      // floor, and a short chunk is never suppressed at all.
      final short = Int16List.fromList([...quiet, ...unvoiced]);
      expect(trimToSpeech(_chunk(short)), isNotNull);
    });
  });

  group('the audio and its position stay together', () {
    test('the wav holds exactly the samples the position claims', () {
      final trimmed = trimToSpeech(_chunk(audio))!;
      final header = ByteData.view(
        trimmed.wav.buffer,
        trimmed.wav.offsetInBytes,
        trimmed.wav.lengthInBytes,
      );

      expect(String.fromCharCodes(trimmed.wav.sublist(0, 4)), 'RIFF');
      expect(header.getUint32(24, Endian.little), 16000);
      final dataBytes = header.getUint32(40, Endian.little);
      expect(dataBytes, trimmed.wav.lengthInBytes - 44);
      // The length the caller will publish as this audio's duration must be the
      // length of the audio itself. A word placed against a duration the bytes
      // do not have is placed at a moment nobody spoke.
      expect(dataBytes ~/ 2 * 1000 ~/ 16000, trimmed.durationMs);
    });

    test('the trimmed audio is the same samples, at the same offset', () {
      final trimmed = trimToSpeech(_chunk(audio))!;
      final sent = Int16List.view(
        trimmed.wav.buffer,
        trimmed.wav.offsetInBytes + 44,
        (trimmed.wav.lengthInBytes - 44) ~/ 2,
      );
      final from = trimmed.startMs * 16000 ~/ 1000;

      // Not a sample of its own is altered, reordered or resampled -- the trim
      // chooses a window and copies it.
      expect(sent.length, greaterThan(16000));
      for (final at in [0, 1, 999, sent.length ~/ 2, sent.length - 1]) {
        expect(sent[at], audio[from + at], reason: 'sample $at moved');
      }
    });

    test('stereo is downmixed and sliced on whole frames', () {
      // Interleaved audio sliced mid-frame swaps the channels from that point
      // on, which would hand the voicing test nonsense and put the samples out
      // of order for the provider too.
      final mono = _range(audio, 0, 40.4);
      final stereo = Int16List(mono.length * 2);
      for (var i = 0; i < mono.length; i++) {
        stereo[i * 2] = mono[i];
        stereo[i * 2 + 1] = mono[i];
      }
      final trimmed = trimToSpeech(_chunk(stereo, channels: 2));

      expect(trimmed, isNotNull);
      // The same stretch of the call as the mono run found.
      expect(trimmed!.startMs, inInclusiveRange(19000, _speechStartMs + 500));
      final header = ByteData.view(
        trimmed.wav.buffer,
        trimmed.wav.offsetInBytes,
        trimmed.wav.lengthInBytes,
      );
      expect(header.getUint16(22, Endian.little), 2, reason: 'still stereo');
      final dataBytes = header.getUint32(40, Endian.little);
      expect(dataBytes % 4, 0, reason: 'a whole number of stereo frames');
    });
  });
}
