import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streamed_stt_embed.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';

StreamingSttSendData _data({
  required String text,
  required String original,
  required bool edited,
  List<SttWord> words = const <SttWord>[],
  String service = 'deepgram',
  String langCode = 'en',
}) => StreamingSttSendData(
  text: text,
  originalAsrText: original,
  isEdited: edited,
  editDistance: sttEditDistance(original, text),
  words: words,
  service: service,
  langCode: langCode,
);

void main() {
  const words = [
    SttWord(word: 'hola', start: 0.0, end: 0.4, confidence: 0.9),
    SttWord(word: 'mundo', start: 0.4, end: 0.9, confidence: 0.8),
  ];

  group('streamedSttResponse (the SpeechToTextResponseModel for the send)', () {
    test('verbatim send: text == original, tokens empty, word_timings CARRIED, '
        'service + langCode set', () {
      final model = streamedSttResponse(
        _data(
          text: 'hola mundo',
          original: 'hola mundo',
          edited: false,
          words: words,
        ),
        langCode: 'en',
      );

      expect(model.hasUsableTranscript, isTrue);
      expect(model.transcript.text, 'hola mundo');
      expect(model.transcript.sttTokens, isEmpty); // skip_tokenize base
      expect(model.transcript.langCode, 'en');
      expect(model.service, 'deepgram');
      // Verbatim: timings align with the sent text, so they are carried.
      expect(model.transcript.wordTimings, isNotNull);
      expect(model.transcript.wordTimings!.length, 2);
      expect(model.transcript.wordTimings!.first.word, 'hola');
      expect(model.transcript.wordTimings!.first.startTimeMs, 0);
      expect(model.transcript.wordTimings!.first.endTimeMs, 400);
      expect(
        model.transcript.wordTimings!.first.confidence,
        90,
      ); // 0.9 -> 0..100
    });

    test('edited send: word_timings OMITTED (they align with original ASR, not '
        'the edited text) — D8', () {
      final model = streamedSttResponse(
        _data(
          text: 'hola mundo!',
          original: 'ola mundo',
          edited: true,
          words: words,
        ),
        langCode: 'en',
      );

      expect(model.transcript.text, 'hola mundo!'); // the EDITED text is sent
      expect(model.transcript.wordTimings, isNull); // omitted when edited
      expect(model.transcript.sttTokens, isEmpty);
    });

    test('no words: still usable, word_timings null, does not throw', () {
      final model = streamedSttResponse(
        _data(text: 'hola', original: 'hola', edited: false),
        langCode: 'en',
      );
      expect(model.hasUsableTranscript, isTrue);
      expect(model.transcript.wordTimings, isNull);
    });
  });

  group('streamedUserSttEmbed (the user_stt map written to the event)', () {
    test(
      'verbatim: base STT shape + provenance keys (edited=false, distance 0, '
      'original == text)',
      () {
        final embed = streamedUserSttEmbed(
          _data(
            text: 'hola mundo',
            original: 'hola mundo',
            edited: false,
            words: words,
          ),
          langCode: 'en',
        );

        // Base shape round-trips through the real model.
        final parsed = SpeechToTextResponseModel.fromJson(embed);
        expect(parsed.transcript.text, 'hola mundo');
        expect(parsed.transcript.wordTimings, isNotNull);

        // Provenance keys at the TOP LEVEL where the flag reader looks.
        expect(embed[SttProvenanceKeys.edited], isFalse);
        expect(embed[SttProvenanceKeys.editDistance], 0);
        expect(embed[SttProvenanceKeys.originalAsr], 'hola mundo');
        expect(sttTranscriptEditedFromUserStt(embed), isFalse);
      },
    );

    test('edited: provenance keys carry the edit; the flag reader lights up; '
        'word_timings absent from the embed', () {
      final embed = streamedUserSttEmbed(
        _data(
          text: 'hola mundo',
          original: 'ola mundo',
          edited: true,
          words: words,
        ),
        langCode: 'en',
      );

      final parsed = SpeechToTextResponseModel.fromJson(embed);
      expect(parsed.transcript.text, 'hola mundo'); // edited text is embedded
      expect(parsed.transcript.wordTimings, isNull);

      expect(embed[SttProvenanceKeys.edited], isTrue);
      expect(embed[SttProvenanceKeys.editDistance], 1);
      expect(embed[SttProvenanceKeys.originalAsr], 'ola mundo');
      expect(sttTranscriptEditedFromUserStt(embed), isTrue);
    });

    test('the transcript text embedded is the SENT text so the bot replies to '
        'what the learner approved (edited), not the raw ASR', () {
      final embed = streamedUserSttEmbed(
        _data(text: 'corrected', original: 'raw asr', edited: true),
        langCode: 'en',
      );
      final parsed = SpeechToTextResponseModel.fromJson(embed);
      expect(parsed.transcript.text, 'corrected');
      expect(parsed.transcript.text, isNot('raw asr'));
    });
  });

  group(
    'userSttEmbedFromModel (the EXACT expression onVoiceMessageSend writes)',
    () {
      test(
        'merges the built model json with the D9 provenance keys at top level, '
        'preserving both',
        () {
          final data = _data(
            text: 'hola mundo',
            original: 'ola mundo',
            edited: true,
            words: words,
          );
          final model = streamedSttResponse(data, langCode: 'en');
          final embed = userSttEmbedFromModel(model, data);

          // Base model shape survives (bot reads the sent text).
          expect(
            SpeechToTextResponseModel.fromJson(embed).transcript.text,
            'hola mundo',
          );
          // Provenance keys present at the flag-reader level.
          expect(embed[SttProvenanceKeys.edited], isTrue);
          expect(embed[SttProvenanceKeys.editDistance], 1);
          expect(embed[SttProvenanceKeys.originalAsr], 'ola mundo');
          // Teeth: dropping the provenance spread (production's merge) loses the flag.
          expect(sttTranscriptEditedFromUserStt(embed), isTrue);
        },
      );
    },
  );

  group(
    'voiceSendIsDecoupled (streamed ALWAYS enriches; batch only when flagged)',
    () {
      test('streamed send decouples EVEN with the Phase-1 flag OFF (it embeds '
          'empty tokens, so tokens must attach in the background)', () {
        // Teeth: pre-fix the streamed send only enriched when the batch flag was
        // on, so tokens would silently never attach with the flag off.
        expect(
          voiceSendIsDecoupled(decoupleFlag: false, isStreamedSend: true),
          isTrue,
        );
      });

      test('batch send with flag OFF does NOT decouple (byte-identical legacy '
          'inline-analytics path)', () {
        expect(
          voiceSendIsDecoupled(decoupleFlag: false, isStreamedSend: false),
          isFalse,
        );
      });

      test(
        'batch send with flag ON decouples (unchanged Phase-1 behaviour)',
        () {
          expect(
            voiceSendIsDecoupled(decoupleFlag: true, isStreamedSend: false),
            isTrue,
          );
        },
      );
    },
  );
}
