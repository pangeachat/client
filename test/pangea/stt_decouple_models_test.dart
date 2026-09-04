import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/audio_encoding_enum.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// P1b.1 — request models + response model for the tokenizer-decouple.
///
/// Covers the four frozen contract points:
///  - `skip_tokenize` is sent, namespaced into the STT cache slot, and folded
///    into equality/hash; the weak 10-byte audio identity is replaced by a full
///    sha256 content digest (so two different short takes never collide).
///  - the `/tokenize` request key distinguishes `langCode` (previously omitted
///    from identity/hash despite being sent).
///  - `word_timings` round-trips but is omit-when-null so a normal response is
///    byte-identical to today; `hasUsableTokens` is true only with non-empty
///    tokens.

/// A SINGLE shared config instance. Held constant across the identity tests so
/// that when two requests differ only in `skipTokenize`, equality/hash cannot
/// pass "by accident" via two distinct config objects -- the ONLY difference is
/// the flag under test (SpeechToTextAudioConfigModel has no value-equality, so a
/// fresh config per request would make requests unequal regardless of the flag).
final _sharedConfig = SpeechToTextAudioConfigModel(
  encoding: AudioEncodingEnum.linear16,
  userL1: 'en',
  userL2: 'es',
);

SpeechToTextRequestModel _req(Uint8List audio, {bool skipTokenize = false}) =>
    SpeechToTextRequestModel(
      audioContent: audio,
      config: _sharedConfig,
      skipTokenize: skipTokenize,
    );

void main() {
  group('SpeechToTextRequestModel — skip_tokenize + sha256 identity', () {
    final audio = Uint8List.fromList(List<int>.generate(64, (i) => i));

    test(
      'skip_tokenize is sent ONLY when true; flag-OFF omits it so the request '
      'bytes are byte-identical to today',
      () {
        expect(
          _req(audio, skipTokenize: true).toJson()['skip_tokenize'],
          isTrue,
        );
        // Flag OFF: the key is absent entirely (not `false`), so a decouple-OFF
        // request serializes exactly as it did before this feature existed.
        expect(
          _req(
            audio,
            skipTokenize: false,
          ).toJson().containsKey('skip_tokenize'),
          isFalse,
        );
      },
    );

    test('with config + audio held CONSTANT, ONLY skipTokenize distinguishes the '
        'cache slot / equality / hash / set membership', () {
      // Same audio instance, same shared config -> the sole difference is the
      // flag. Removing skipTokenize from storageKey/==/hashCode turns this RED.
      final full = _req(audio, skipTokenize: false);
      final skip = _req(audio, skipTokenize: true);

      expect(
        full.storageKey,
        isNot(skip.storageKey),
        reason:
            'a skip_tokenize request must never share a cache slot with a '
            'full one for the same audio',
      );
      expect(full == skip, isFalse);
      expect(full.hashCode == skip.hashCode, isFalse);
      expect({full, skip, _req(audio, skipTokenize: false)}, hasLength(2));
    });

    test('storageKey uses a full sha256 content digest of the audio', () {
      final key = _req(audio, skipTokenize: true).storageKey;
      final digest = sha256.convert(audio).toString();
      expect(
        key.contains(digest),
        isTrue,
        reason: 'the storage key must embed the sha256 of the full audio',
      );
    });

    test('two different takes sharing a codec header do NOT collide (the R0 '
        '10-byte-prefix weakness)', () {
      // Same fixed 12-byte "header", different bodies of the same length.
      final header = List<int>.generate(12, (i) => i);
      final a = Uint8List.fromList([...header, ...List.filled(40, 1)]);
      final b = Uint8List.fromList([...header, ...List.filled(40, 2)]);
      final ra = _req(a, skipTokenize: true);
      final rb = _req(b, skipTokenize: true);
      expect(ra.storageKey, isNot(rb.storageKey));
      expect(ra == rb, isFalse);
    });
  });

  group('TokensRequestModel — langCode in identity/hash', () {
    TokensRequestModel model(String? langCode) => TokensRequestModel(
      fullText: 'hola mundo',
      senderL1: 'en',
      senderL2: 'es',
      langCode: langCode,
    );

    test('two requests differing only in langCode are non-equal', () {
      expect(model('es') == model('fr'), isFalse);
      expect(model('es').hashCode == model('fr').hashCode, isFalse);
    });

    test('langCode is part of the storage key', () {
      expect(model('es').storageKey, isNot(model('fr').storageKey));
    });

    test('a Set treats them as distinct members', () {
      final set = {model('es'), model('fr'), model('es')};
      expect(set.length, 2);
    });

    test('sender_l1/sender_l2 remain part of the key', () {
      final base = model('es');
      final diffL1 = TokensRequestModel(
        fullText: 'hola mundo',
        senderL1: 'de',
        senderL2: 'es',
        langCode: 'es',
      );
      expect(base == diffL1, isFalse);
      expect(base.storageKey, isNot(diffL1.storageKey));
    });
  });

  group('SpeechToTextResponseModel — word_timings + hasUsableTokens', () {
    Map<String, dynamic> normalJson() => {
      'results': [
        {
          'transcripts': [
            {
              'confidence': 94,
              'lang_code': 'es',
              'stt_tokens': <Map<String, dynamic>>[],
              'transcript': 'hola mundo',
              'words_per_hr': 120,
            },
          ],
        },
      ],
      'service': 'google',
    };

    test(
      'a null-word_timings response serializes byte-identically to today',
      () {
        // No `word_timings` key, no `stt_tokens` change — the omit-when-null
        // guarantee that keeps flag-off wire bytes identical.
        final model = SpeechToTextResponseModel.fromJson(normalJson());
        final out = model.toJson();
        final transcript =
            (out['results'][0]['transcripts'][0]) as Map<String, dynamic>;
        expect(transcript.containsKey('word_timings'), isFalse);
        expect(transcript['stt_tokens'], isEmpty);
        expect(transcript['transcript'], 'hola mundo');
      },
    );

    test('word_timings round-trips through the model', () {
      final json = normalJson();
      (json['results'][0]['transcripts'][0]
          as Map<String, dynamic>)['word_timings'] = [
        {
          'word': 'hola',
          'start_time_ms': 0,
          'end_time_ms': 480,
          'confidence': 98,
        },
        {
          'word': 'mundo',
          'start_time_ms': 480,
          'end_time_ms': 960,
          'confidence': 91,
        },
      ];
      final model = SpeechToTextResponseModel.fromJson(json);
      final timings = model.transcript.wordTimings!;
      expect(timings, hasLength(2));
      expect(timings.first.word, 'hola');
      expect(timings.first.startTimeMs, 0);
      expect(timings.first.endTimeMs, 480);
      expect(timings.first.confidence, 98);

      final out =
          (model.toJson()['results'][0]['transcripts'][0])
              as Map<String, dynamic>;
      expect(
        out['word_timings'],
        json['results'][0]['transcripts'][0]['word_timings'],
      );
    });

    test('word_timings tolerates null timestamps (never fabricated)', () {
      final json = normalJson();
      (json['results'][0]['transcripts'][0]
          as Map<String, dynamic>)['word_timings'] = [
        {
          'word': 'hola',
          'start_time_ms': null,
          'end_time_ms': null,
          'confidence': 0,
        },
      ];
      final model = SpeechToTextResponseModel.fromJson(json);
      final wt = model.transcript.wordTimings!.first;
      expect(wt.startTimeMs, isNull);
      expect(wt.endTimeMs, isNull);
      expect(wt.confidence, 0);
    });

    test('WordTiming.confidence is normalized to a bounded 0..100 int '
        '(fractions rounded, out-of-range clamped)', () {
      // Bang, because fromJson is nullable now: an entry it cannot read costs
      // the timings rather than throwing and costing the words with them. Every
      // confidence below IS readable, so a null here would be a real failure.
      WordTiming parse(Object confidence) => WordTiming.fromJson({
        'word': 'hola',
        'start_time_ms': 0,
        'end_time_ms': 100,
        'confidence': confidence,
      })!;

      // Fraction -> rounded int (never a fractional confidence).
      expect(parse(98.6).confidence, 99);
      expect(parse(0.4).confidence, 0);
      // Out of range -> clamped to the frozen 0..100 contract.
      expect(parse(150).confidence, 100);
      expect(parse(-5).confidence, 0);
      expect(parse(250.9).confidence, 100);
      // In-range values pass through unchanged, incl. a valid 0.
      expect(parse(0).confidence, 0);
      expect(parse(73).confidence, 73);
    });

    group('a response a provider malformed', () {
      // The rule these all pin: a defect in a field BESIDE the text must never
      // cost the text. The parse used to couple them -- one bad timing entry
      // threw, the throw came out of the whole response parse, and the sink
      // that catches it marks the chunk failed and counts it LOST. Up to ninety
      // seconds of somebody's speech, for one malformed number.
      Map<String, dynamic> withTimings(List<Object?> timings) {
        final json = normalJson();
        (json['results'][0]['transcripts'][0]
                as Map<String, dynamic>)['word_timings'] =
            timings;
        return json;
      }

      final unreadable = <String, List<Object?>>{
        'a missing word': [
          {'start_time_ms': 0, 'end_time_ms': 100, 'confidence': 90},
        ],
        'a non-string word': [
          {'word': 7, 'start_time_ms': 0, 'end_time_ms': 100, 'confidence': 90},
        ],
        'a missing confidence': [
          {'word': 'hola', 'start_time_ms': 0, 'end_time_ms': 100},
        ],
        'a non-numeric confidence': [
          {
            'word': 'hola',
            'start_time_ms': 0,
            'end_time_ms': 100,
            'confidence': 'high',
          },
        ],
        'a NaN confidence': [
          {
            'word': 'hola',
            'start_time_ms': 0,
            'end_time_ms': 100,
            'confidence': double.nan,
          },
        ],
        'an infinite timestamp': [
          {
            'word': 'hola',
            'start_time_ms': double.infinity,
            'end_time_ms': 100,
            'confidence': 90,
          },
        ],
        'a non-numeric timestamp': [
          {
            'word': 'hola',
            'start_time_ms': 'start',
            'end_time_ms': 100,
            'confidence': 90,
          },
        ],
        'an entry that is not a map': ['hola'],
        'a null entry': [null],
        'one bad entry among good ones': [
          {
            'word': 'hola',
            'start_time_ms': 0,
            'end_time_ms': 100,
            'confidence': 90,
          },
          {'word': 'mundo', 'end_time_ms': 300, 'confidence': 'high'},
        ],
      };

      unreadable.forEach((what, timings) {
        test('$what costs the timings and keeps the words', () {
          final model = SpeechToTextResponseModel.fromJson(
            withTimings(timings),
          );

          expect(model.hasUsableTranscript, isTrue);
          expect(model.transcript.text, 'hola mundo');
          expect(
            model.transcript.wordTimings,
            isNull,
            reason: 'all or nothing: a partial list moves where the cuts land',
          );
        });
      });

      test('and a readable list is still read', () {
        // The control. Without it every assertion above would still hold with
        // word timings removed from the model altogether.
        final model = SpeechToTextResponseModel.fromJson(
          withTimings([
            {
              'word': 'hola',
              'start_time_ms': 0,
              'end_time_ms': 100,
              'confidence': 90,
            },
          ]),
        );

        expect(model.transcript.wordTimings, hasLength(1));
        expect(model.transcript.wordTimings!.single.word, 'hola');
      });

      test('a word_timings that is not a list at all is simply absent', () {
        final json = normalJson();
        (json['results'][0]['transcripts'][0]
                as Map<String, dynamic>)['word_timings'] =
            'hola';

        final model = SpeechToTextResponseModel.fromJson(json);
        expect(model.transcript.wordTimings, isNull);
        expect(model.transcript.text, 'hola mundo');
      });

      test('an unreadable token list costs the tokens and keeps the words', () {
        // Tokens are the ANALYTICS. Empty is a state this app already produces
        // deliberately on the skip-tokenize path, and every consumer gates on
        // hasUsableTokens.
        final json = normalJson();
        (json['results'][0]['transcripts'][0]
            as Map<String, dynamic>)['stt_tokens'] = [
          'not a token',
        ];

        final model = SpeechToTextResponseModel.fromJson(json);
        expect(model.hasUsableTranscript, isTrue);
        expect(model.transcript.text, 'hola mundo');
        expect(model.hasUsableTokens, isFalse);
        expect(model.transcript.sttTokens, isEmpty);
      });

      test('unreadable metadata costs the metadata and keeps the words', () {
        // service, confidence, lang_code and words_per_hr are decoration and
        // provenance beside the speech. Each of them threw before.
        final json = normalJson();
        json['service'] = 42;
        final transcript =
            json['results'][0]['transcripts'][0] as Map<String, dynamic>;
        transcript['confidence'] = 'very';
        transcript['lang_code'] = 7;
        transcript['words_per_hr'] = 1.5;

        final model = SpeechToTextResponseModel.fromJson(json);
        expect(model.hasUsableTranscript, isTrue);
        expect(model.transcript.text, 'hola mundo');
        expect(model.service, isNull);
        expect(model.transcript.confidence, 0);
        expect(model.transcript.langCode, '', reason: 'empty means unknown');
        expect(model.transcript.wordsPerHr, 1);
      });

      test('a double-scaled transcript confidence no longer throws', () {
        // `confidence / 100` produces a DOUBLE, which went straight into an int
        // field: a confidence of 250 threw a type error out of the parse and
        // cost the chunk its words.
        final json = normalJson();
        (json['results'][0]['transcripts'][0]
                as Map<String, dynamic>)['confidence'] =
            250;

        final model = SpeechToTextResponseModel.fromJson(json);
        expect(model.transcript.confidence, 3);
        expect(model.transcript.text, 'hola mundo');
      });

      test('a conforming confidence passes through untouched', () {
        final model = SpeechToTextResponseModel.fromJson(normalJson());
        expect(model.transcript.confidence, 94);
      });
    });

    test('hasUsableTokens is false when tokens are empty, true otherwise', () {
      final skip = SpeechToTextResponseModel.fromJson(normalJson());
      expect(skip.hasUsableTranscript, isTrue);
      expect(skip.hasUsableTokens, isFalse);

      final withTokens = SpeechToTextResponseModel.fromJson(
        jsonDecode(
              jsonEncode({
                'results': [
                  {
                    'transcripts': [
                      {
                        'confidence': 94,
                        'lang_code': 'es',
                        'stt_tokens': [
                          {
                            'token': {
                              'text': {
                                'content': 'hola',
                                'offset': 0,
                                'length': 4,
                              },
                              'lemma': {
                                'text': 'hola',
                                'save_vocab': true,
                                'form': 'hola',
                              },
                              'pos': 'INTJ',
                              'morph': <String, dynamic>{},
                            },
                            'start_time': 0,
                            'end_time': 480,
                            'confidence': 98,
                          },
                        ],
                        'transcript': 'hola',
                        'words_per_hr': 120,
                      },
                    ],
                  },
                ],
                'service': 'google',
              }),
            )
            as Map<String, dynamic>,
      );
      expect(withTokens.hasUsableTokens, isTrue);
    });

    test(
      'hasUsableTokens is false on an exhausted-fallback (empty) response',
      () {
        final empty = SpeechToTextResponseModel(results: const []);
        expect(empty.hasUsableTranscript, isFalse);
        expect(empty.hasUsableTokens, isFalse);
      },
    );
  });

  group('buildVoiceSttRequest — H3 single t0 language snapshot', () {
    final audio = Uint8List.fromList([1, 2, 3, 4]);

    test('the ASR config uses the EXPLICITLY passed languages, never current '
        'settings', () {
      final req = buildVoiceSttRequest(
        audioContent: audio,
        mimeType: 'audio/x-wav',
        userL1: 'en',
        userL2: 'es',
        skipTokenize: false,
      );
      // Teeth: if this re-read MatrixState.pangeaController (the regression),
      // there is no MatrixState under `flutter test` -> throw/wrong value -> RED.
      expect(req.config.userL1, 'en');
      expect(req.config.userL2, 'es');
    });

    test('BLOCKER: VoiceSendLanguages captures the EMBED raw locale AND the ASR '
        'short code from one t0 read -> ASR carries the short code (flag-OFF '
        'byte-equivalent), NOT the full locale', () {
      // A user whose source setting is a full locale (es-MX) whose language
      // model short-code is `es` -- the baseline ASR built its config from the
      // SHORT code, so the ASR must carry `es`, not `es-MX`.
      final langs = VoiceSendLanguages.capture(
        sourceCode: 'es-MX', // userL1Code (embed)
        targetCode: 'en-US', // userL2Code (embed)
        sourceShort: 'es', // userL1?.langCodeShort (ASR)
        targetShort: 'en', // userL2?.langCodeShort (ASR)
      );

      // The EMBED keeps the raw locale (baseline speaker_l1/l2).
      expect(langs.speakerL1, 'es-MX');
      expect(langs.speakerL2, 'en-US');
      // The ASR uses the SHORT code (baseline ASR hint). Teeth: sourcing asrL1
      // from sourceCode (the R4 regression) makes this `es-MX` -> RED.
      expect(langs.asrL1, 'es');
      expect(langs.asrL2, 'en');

      // And the ASR request built from it carries the short code.
      final asrReq = buildVoiceSttRequest(
        audioContent: audio,
        mimeType: 'audio/x-wav',
        userL1: langs.asrL1,
        userL2: langs.asrL2,
        skipTokenize: false,
      );
      expect(asrReq.config.userL1, 'es');
      expect(asrReq.config.userL2, 'en');
    });

    test(
      'VoiceSendLanguages falls back to unknownLanguage for the ASR when the '
      'short code is null (no language model)',
      () {
        final langs = VoiceSendLanguages.capture(
          sourceCode: 'xx',
          targetCode: null,
          sourceShort: null,
          targetShort: null,
        );
        expect(langs.speakerL1, 'xx'); // embed keeps the raw code
        expect(langs.asrL1, isNotNull); // ASR never null
        expect(langs.asrL1, isNot('xx'));
      },
    );
  });
}
