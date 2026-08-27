import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// One second of audio at [sampleRate], placed at [startedAtMs].
PcmChunk chunk(int index, {int sampleRate = 16000, int startedAtMs = 1000}) =>
    PcmChunk(
      pcm: Uint8List(sampleRate * 2),
      sampleRate: sampleRate,
      channels: 1,
      index: index,
      startedAtMs: startedAtMs,
    );

/// An empty-but-valid response — the shape the route returns when nothing was
/// transcribable, which is a normal answer rather than a failure.
SpeechToTextResponseModel get silent =>
    SpeechToTextResponseModel(results: const []);

/// A response carrying one usable word.
SpeechToTextResponseModel get spoken => spokenWord('hola');

/// One transcribed word, in the shape the route actually returns — taken from a
/// real response so the test exercises the same parse the app does.
/// [timed] adds a word timing spanning the first tenth of a second, which is
/// what a chunk needs before its segment can be placed at all.
SpeechToTextResponseModel spokenWord(
  String word, {
  String langCode = 'es-ES',
  bool timed = false,
}) => SpeechToTextResponseModel.fromJson({
  'results': [
    {
      'transcripts': [
        {
          'transcript': word,
          'confidence': 100,
          'lang_code': langCode,
          'words_per_hr': 9391,
          if (timed)
            'word_timings': [
              {
                'word': word,
                'start_time_ms': 0,
                'end_time_ms': 100,
                'confidence': 100,
              },
            ],
          'stt_tokens': [
            {
              'token': {
                'text': {'offset': 0, 'content': word, 'length': word.length},
                'lemma': [
                  {
                    'text': word,
                    'form': word,
                    'lang': 'es',
                    'save_vocab': true,
                  },
                ],
                'pos': 'INTJ',
                'morph': {'Pos': 'INTJ'},
              },
              'start_time': 0,
              'end_time': 400,
              'confidence': 100,
            },
          ],
        },
      ],
    },
  ],
});

void main() {
  late List<SpeechToTextRequestModel> sent;

  CallTranscriptSink sink({
    SpeechToTextResponseModel Function(int call)? respond,
    Set<int> failOn = const {},
    Set<int> hangOn = const {},
  }) {
    sent = [];
    return CallTranscriptSink(
      userL1: 'en',
      userL2: 'es',
      transcribe: (request) async {
        final index = sent.length;
        sent.add(request);
        if (failOn.contains(index)) throw StateError('provider refused');
        // Never answers, and is never cancelled — a request that has gone quiet
        // rather than one that failed.
        if (hangOn.contains(index)) await Completer<void>().future;
        return respond?.call(index) ?? silent;
      },
    );
  }

  group('a request that goes quiet', () {
    test('is given up on, and the next attempt is a real one', () async {
      // The first request never answers. A limit that only stopped the CALLER
      // waiting left it listed as in flight, so the retry joined the same dead
      // request and all three attempts were one.
      final s = sink(hangOn: {0}, respond: (_) => spoken);
      final within = const Duration(milliseconds: 50);

      await expectLater(
        s.deliver(chunk(0), within: within),
        throwsA(isA<TimeoutException>()),
      );
      expect(sent, hasLength(1));

      await s.deliver(chunk(0), within: within);
      expect(
        sent,
        hasLength(2),
        reason: 'the retry has to reach the provider, not the abandoned call',
      );
      expect(s.hasTranscript, isTrue);
    });
  });

  group('CallTranscriptSink', () {
    test('sends each chunk as WAV at the rate it was captured', () async {
      final s = sink();
      await s.deliver(chunk(0));

      expect(sent, hasLength(1));
      expect(sent.single.config.sampleRateHertz, 16000);
      expect(sent.single.config.userL1, 'en');
      expect(sent.single.config.userL2, 'es');
      expect(
        String.fromCharCodes(sent.single.audioContent.sublist(0, 4)),
        'RIFF',
        reason: 'the route takes a container, not bare samples',
      );
    });

    test('a chunk is transcribed once however often it is delivered', () async {
      // The route is billed per call, and appending the same words twice would
      // credit the learner twice for saying something once.
      final s = sink();
      await s.deliver(chunk(0));
      await s.deliver(chunk(0));
      await s.deliver(chunk(1));
      await s.deliver(chunk(0));

      expect(sent, hasLength(2));
      expect(s.chunkCount, 2);
    });

    test('the transcript view cannot be used to change the call', () async {
      // The provider's response objects are mutable all the way down. Handing
      // them out would let a caller empty one and change what the call is worth.
      final s = sink(respond: (_) => spoken);
      await s.deliver(chunk(0));

      final before = s.transcripts;
      expect(before, ['hola']);
      before.clear();

      expect(s.transcripts, ['hola']);
      expect(s.hasTranscript, isTrue);
      expect(s.constructs(roomId: '!r:server', eventId: '\$e'), isNotEmpty);
    });

    test('a chunk that fails says so, and costs no other chunk', () async {
      // The failure is reported rather than swallowed. The caller's whole
      // purpose is to try again, and telling it everything went well meant one
      // bad moment from the provider cost that chunk's words for good.
      final s = sink(failOn: {0});

      await expectLater(s.deliver(chunk(0)), throwsA(isA<StateError>()));
      await s.deliver(chunk(1));

      expect(sent, hasLength(2), reason: 'the call carried on');
      expect(s.chunkCount, 1);
    });

    test('a chunk that failed can be transcribed on a later attempt', () async {
      // Only a chunk that was actually transcribed must never be transcribed
      // again. One that was not has nothing to double-count, and holding its
      // place made every retry a no-op.
      final s = sink(failOn: {0});

      await expectLater(s.deliver(chunk(0)), throwsA(isA<StateError>()));
      await s.deliver(chunk(0));

      expect(sent, hasLength(2), reason: 'the second attempt really ran');
      expect(s.chunkCount, 1, reason: 'and it landed');
    });

    test(
      'a response with an empty nested transcript is not a transcript',
      () async {
        // A 200 whose results carry no usable text is a real answer, and reading
        // its transcript throws — so it must not be reported as transcript-bearing.
        final s = sink(
          respond: (_) => SpeechToTextResponseModel.fromJson({
            'results': [
              {'transcripts': []},
            ],
          }),
        );
        await s.deliver(chunk(0));

        expect(s.hasTranscript, isFalse);
        expect(s.langCode, isNull);
        expect(s.constructs(roomId: '!r:server', eventId: '\$e'), isEmpty);
      },
    );

    test('reports whether anything was actually said', () async {
      final s = sink();
      expect(s.hasTranscript, isFalse);
      await s.deliver(chunk(0));
      expect(
        s.hasTranscript,
        isFalse,
        reason: 'a silent chunk is a real answer, not a transcript',
      );
    });

    test('a call that transcribed nothing produces no constructs', () async {
      final s = sink();
      await s.deliver(chunk(0));
      expect(s.constructs(roomId: '!r:server', eventId: '\$e'), isEmpty);
      expect(s.langCode, isNull);
    });

    test('a use is built once and never rebuilt', () async {
      // Comparing lengths is not enough: each use is stamped with the moment it
      // was built, so a rebuilt one would differ from the one already recorded
      // while the batch still had the same size.
      final s = sink(respond: (_) => spoken);
      await s.deliver(chunk(0));
      final first = s.constructs(roomId: '!r:server', eventId: '\$e');
      final second = s.constructs(roomId: '!r:server', eventId: '\$e');

      expect(first, isNotEmpty);
      for (var i = 0; i < first.length; i++) {
        expect(second[i].timeStamp, first[i].timeStamp);
        expect(second[i].lemma, first[i].lemma);
        expect(second[i].xp, first[i].xp);
      }
    });

    test('a caller cannot change what a later read returns', () async {
      // A use is a mutable object. Handing out the cached one would let any
      // caller rewrite the recorded credit.
      final s = sink(respond: (_) => spoken);
      await s.deliver(chunk(0));

      final first = s.constructs(roomId: '!r:server', eventId: '\$e');
      final originalXp = first.first.xp;
      first.first.xp = 0;
      first.first.lemma = 'tampered';

      final second = s.constructs(roomId: '!r:server', eventId: '\$e');
      expect(second.first.xp, originalXp);
      expect(second.first.lemma, isNot('tampered'));
    });

    test('a chunk arriving after the batch was read still counts', () async {
      // Caching the whole batch would silently drop it. Credit may only grow.
      final s = sink(respond: (_) => spoken);
      await s.deliver(chunk(0));
      final before = s.constructs(roomId: '!r:server', eventId: '\$e');

      await s.deliver(chunk(1));
      final after = s.constructs(roomId: '!r:server', eventId: '\$e');

      expect(after.length, greaterThan(before.length));
      for (var i = 0; i < before.length; i++) {
        expect(
          after[i].timeStamp,
          before[i].timeStamp,
          reason: 'and the uses already recorded are untouched',
        );
      }
    });

    test('the batch cannot be mutated by whoever receives it', () async {
      final s = sink();
      await s.deliver(chunk(0));
      final uses = s.constructs(roomId: '!r:server', eventId: '\$e');
      expect(() => uses.clear(), throwsUnsupportedError);
    });

    test('transcripts are ordered by when the audio was spoken', () async {
      // Deliveries overlap by design, so a later chunk can come back from the
      // provider first. Ordering by arrival would order the call by latency, so
      // each response here is distinguishable and they arrive out of order.
      const words = ['uno', 'dos', 'tres'];
      var call = 0;
      final s = CallTranscriptSink(
        userL1: 'en',
        userL2: 'es',
        transcribe: (_) async => spokenWord(words[call++]),
      );

      await s.deliver(chunk(2));
      await s.deliver(chunk(0));
      await s.deliver(chunk(1));

      expect(
        s.transcripts,
        // chunk 2 was transcribed first, so it holds 'uno'; ordering by arrival
        // would put it first instead of last.
        ['dos', 'tres', 'uno'],
      );
    });

    test(
      'the language comes from the earliest chunk, not the fastest',
      () async {
        var call = 0;
        final s = CallTranscriptSink(
          userL1: 'en',
          userL2: 'es',
          transcribe: (_) async =>
              spokenWord('w', langCode: call++ == 0 ? 'de-DE' : 'es-ES'),
        );

        await s.deliver(chunk(1));
        await s.deliver(chunk(0));

        expect(s.langCode, 'es', reason: 'chunk 0 is the call\'s language');
      },
    );

    test(
      'one chunk failing does not stop close waiting for the rest',
      () async {
        // BOTH are still running when the call ends. A failure arrives here as
        // an error on a future, and letting it out of the wait made close()
        // itself throw: the caller then treated the whole flush as failed, and
        // the loop that is the only thing watching for a chunk retried WHILE we
        // waited never ran again.
        final failing = Completer<SpeechToTextResponseModel>();
        final slow = Completer<SpeechToTextResponseModel>();
        var calls = 0;
        final s = CallTranscriptSink(
          userL1: 'en',
          userL2: 'es',
          transcribe: (_) => calls++ == 0 ? failing.future : slow.future,
        );

        unawaited(s.deliver(chunk(0)).catchError((_) {}));
        unawaited(s.deliver(chunk(1)));
        await pumpEventQueue();

        final closing = s.close();
        failing.completeError(StateError('provider refused'));
        slow.complete(spokenWord('hola'));

        await closing;
        expect(
          s.hasTranscript,
          isTrue,
          reason: 'the chunk that DID come back was not kept',
        );
      },
    );

    test('call speech is credited as pvc, which counts as speaking', () {
      // The type the client emits has to be one the server scores; an unknown
      // one silently scores zero rather than failing.
      expect(
        ConstructUseTypeEnum.pvc.pointValue,
        ConstructUseTypeEnum.pvm.pointValue,
      );
      expect(
        ConstructUseTypeEnum.pvc.skillsEnumType,
        ConstructUseTypeEnum.pvm.skillsEnumType,
      );
    });
  });

  group('where each chunk sat', () {
    test('a segment is placed by the audio it came from', () async {
      final s = sink(respond: (call) => spokenWord('w$call', timed: true));
      await s.deliver(chunk(0, startedAtMs: 1000));
      await s.deliver(chunk(1, startedAtMs: 2000));

      expect(s.segments.map((segment) => (segment.text, segment.atMs)), [
        ('w0', 1000),
        ('w1', 2000),
      ]);
    });

    test('a chunk that FAILED does not slide its neighbours onto the wrong '
        'words', () async {
      // The failed chunk is recorded in _failed and never reaches _byIndex, so
      // its placement has no response beside it. Zipping the two sorted lists
      // by POSITION would hand chunk 2's words chunk 1's start time, and every
      // later chunk after that.
      final s = sink(
        failOn: {1},
        respond: (call) => spokenWord('w$call', timed: true),
      );
      await s.deliver(chunk(0, startedAtMs: 1000));
      await expectLater(
        s.deliver(chunk(1, startedAtMs: 2000)),
        throwsA(isA<StateError>()),
      );
      await s.deliver(chunk(2, startedAtMs: 3000));

      expect(s.segments.map((segment) => (segment.text, segment.atMs)), [
        ('w0', 1000),
        ('w2', 3000),
      ]);
    });
  });

  group('a chunk whose timings the provider malformed', () {
    test('keeps its words, loses only its position', () async {
      // The whole reason the response parse is tolerant. A throw out of the
      // parse lands in the catch below, which marks the chunk failed and counts
      // it LOST -- so one malformed number cost up to ninety seconds of
      // somebody's speech. Now the words arrive and only the position is
      // withheld, which is the promise this feature makes everywhere else.
      final s = CallTranscriptSink(
        userL1: 'en',
        userL2: 'es',
        transcribe: (_) async => SpeechToTextResponseModel.fromJson({
          'results': [
            {
              'transcripts': [
                {
                  'transcript': 'hola mundo',
                  'confidence': 100,
                  'lang_code': 'es-ES',
                  'words_per_hr': 9391,
                  'stt_tokens': <dynamic>[],
                  'word_timings': [
                    {
                      'word': 'hola',
                      'start_time_ms': 0,
                      'end_time_ms': 100,
                      'confidence': 100,
                    },
                    // The provider dropped this word's confidence.
                    {'word': 'mundo', 'start_time_ms': 150, 'end_time_ms': 300},
                  ],
                },
              ],
            },
          ],
        }),
      );

      await s.deliver(chunk(0, startedAtMs: 1000));

      expect(s.chunksLost, 0, reason: 'nothing was captured and then lost');
      expect(s.transcripts, ['hola mundo']);
      // The chunk's own start, not null. Malformed provider timings cost this
      // chunk its word-level precision; they no longer cost the rest of the
      // call its timeline.
      expect(s.segments.map((segment) => (segment.text, segment.atMs)), [
        ('hola mundo', 1000),
      ]);
    });
  });

  group('a response whose UNREAD parts the provider malformed', () {
    // A sibling result and a sibling alternative are "beside the words" in
    // exactly the way a sibling field is. The call path reads the first usable
    // transcript and never looks past it, so neither of these is ever read --
    // and both used to throw out of the whole parse, land in the catch that
    // marks a chunk failed, and cost up to ninety seconds of speech.
    CallTranscriptSink sinkReturning(Map<String, dynamic> response) =>
        CallTranscriptSink(
          userL1: 'en',
          userL2: 'es',
          transcribe: (_) async => SpeechToTextResponseModel.fromJson(response),
        );

    /// A transcript the provider read as carrying no speech. Legitimate: the
    /// model's own `hasUsableTranscript` exists to report exactly this shape as
    /// parseable but not usable.
    Map<String, dynamic> emptyTranscript() => {
      'transcript': '',
      'confidence': 90,
      'lang_code': 'es-ES',
      'words_per_hr': 0,
      'stt_tokens': <dynamic>[],
    };

    Map<String, dynamic> goodTranscript(String text) => {
      'transcript': text,
      'confidence': 100,
      'lang_code': 'es-ES',
      'words_per_hr': 9391,
      'stt_tokens': <dynamic>[],
    };

    test('a malformed result fails, wherever in the list it sits', () async {
      // This test used to assert the opposite -- that a malformed SECOND result
      // was dropped and the good first one survived. That was wrong, and it was
      // wrong in a way the alternative-level rule below is not.
      //
      // A result is a SEGMENT of the audio and its index is its identity. Every
      // reader across all three repos takes `results[0].transcripts[0]`, so
      // dropping one slides a different piece of the recording into the place
      // the first one meant. And once the list has been compacted, "we could
      // read none of what arrived" and "the provider returned nothing" are
      // indistinguishable -- which let a malformed first result followed by an
      // empty second read as SILENCE.
      //
      // Nothing was lost by giving the tolerance up: all three choreo adapters
      // emit exactly one result, so the shape it defended is not one any
      // producer sends.
      final s = sinkReturning({
        'results': [
          {
            'transcripts': [goodTranscript('hola mundo')],
          },
          {'transcripts': 'not a list'},
        ],
      });

      await expectLater(s.deliver(chunk(0)), throwsA(isA<FormatException>()));

      expect(s.chunksLost, 1, reason: 'captured, and then genuinely lost');
      expect(s.hasTranscript, isFalse);
    });

    test('a malformed FIRST result is never replaced by a later one', () async {
      // The substitution this rule exists to prevent. Dropping the first result
      // promotes the second into `results.first`, so the reader is handed
      // speech from a different part of the recording and nothing anywhere says
      // so. Losing the chunk is the honest outcome; quietly answering with the
      // wrong segment is not.
      final s = sinkReturning({
        'results': [
          {'transcripts': 'not a list'},
          {
            'transcripts': [goodTranscript('otro momento')],
          },
        ],
      });

      await expectLater(s.deliver(chunk(0)), throwsA(isA<FormatException>()));

      expect(s.chunksLost, 1);
      expect(
        s.transcripts,
        isEmpty,
        reason: 'never the second segment standing in for the first',
      );
    });

    test('a malformed first beside an EMPTY second is not silence', () async {
      // The worse half, and the one a compacted list cannot see. Dropping the
      // malformed first leaves a list that is NOT empty -- it holds the
      // empty-transcripts second -- so a guard asking whether anything survived
      // does not fire, and the chunk is reported as the speaker having said
      // nothing. Speech we failed to read, presented as a person's silence.
      final s = sinkReturning({
        'results': [
          {'transcripts': 'not a list'},
          {'transcripts': <dynamic>[]},
        ],
      });

      await expectLater(s.deliver(chunk(0)), throwsA(isA<FormatException>()));

      expect(
        s.chunksLost,
        1,
        reason: 'this is a chunk we lost, not a speaker who was quiet',
      );
      expect(s.hasTranscript, isFalse);
      expect(s.chunksTranscribed, 0);
    });

    test('a malformed SECOND alternative does not cost the first', () async {
      final s = sinkReturning({
        'results': [
          {
            'transcripts': [
              goodTranscript('hola mundo'),
              // Nothing on the call path reads a second alternative.
              {'transcript': 42, 'confidence': 90},
            ],
          },
        ],
      });

      await s.deliver(chunk(0, startedAtMs: 1000));

      expect(s.chunksLost, 0);
      expect(s.transcripts, ['hola mundo']);
    });

    test('a malformed FIRST alternative falls through to the readable one', () {
      // Dropping is positional-blind on purpose. The alternatives are the
      // provider's own ranking, and a lower-ranked one is still speech that was
      // really said -- which beats losing the chunk outright.
      final model = SpeechToTextResponseModel.fromJson({
        'results': [
          {
            'transcripts': [
              {'transcript': 42, 'confidence': 90},
              goodTranscript('hola mundo'),
            ],
          },
        ],
      });

      expect(model.hasUsableTranscript, isTrue);
      expect(model.transcript.text, 'hola mundo');
    });

    test('a malformed alternative beside an EMPTY one is not silence', () async {
      // Dropping an alternative is only honest when a readable one SURVIVES to
      // stand in its place. Here the survivor carries no words, so the result
      // holds one empty alternative: no loss recorded, no usable transcript,
      // and the screen says the speaker SAID NOTHING -- a claim about a person
      // produced from content we could not read.
      final s = sinkReturning({
        'results': [
          {
            'transcripts': [
              {'transcript': 42, 'confidence': 90},
              emptyTranscript(),
            ],
          },
        ],
      });

      await expectLater(s.deliver(chunk(0)), throwsA(isA<FormatException>()));

      expect(
        s.chunksLost,
        1,
        reason: 'this is a chunk we lost, not a speaker who was quiet',
      );
      expect(s.hasTranscript, isFalse);
      expect(s.chunksTranscribed, 0);
    });

    test('an EMPTY first beside a malformed LATER one is still silence', () {
      // The other direction, and the one over-broad scoping got wrong. The
      // reader takes `transcripts[0]`, which is legitimately empty here; the
      // malformed alternative behind it was never going to be read, so it was
      // never a stand-in for anything. Counting this as a lost chunk turns the
      // provider saying it heard nothing into loss.
      final model = SpeechToTextResponseModel.fromJson({
        'results': [
          {
            'transcripts': [
              emptyTranscript(),
              {'transcript': 42, 'confidence': 90},
            ],
          },
        ],
      });

      expect(model.hasUsableTranscript, isFalse);
      expect(model.results, hasLength(1));
    });

    test('an empty survivor behind a readable one is still not a stand-in', () {
      // Tighter than "some survivor has words". The reader takes
      // `transcripts.first`, so a readable alternative sitting BEHIND an empty
      // one is never seen and cannot stand in for what was dropped.
      expect(
        () => SpeechToTextResponseModel.fromJson({
          'results': [
            {
              'transcripts': [
                {'transcript': 42, 'confidence': 90},
                emptyTranscript(),
                goodTranscript('nunca leido'),
              ],
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('an EMPTY transcript with nothing dropped is still silence', () async {
      // The control, and the reason this is decided by what was DROPPED rather
      // than by what survived. An empty transcript is a legitimate answer --
      // `hasUsableTranscript` exists to gate exactly that -- so it must not be
      // turned into a lost chunk just because it carries no words.
      final s = sinkReturning({
        'results': [
          {
            'transcripts': [emptyTranscript()],
          },
        ],
      });

      await s.deliver(chunk(0));

      expect(
        s.chunksLost,
        0,
        reason: 'nothing was dropped, so nothing is lost',
      );
      expect(s.hasTranscript, isFalse);
    });

    test(
      'a response we could read NOTHING in still fails, and is lost',
      () async {
        // The other half of the rule, and the half that keeps dropping honest.
        // Dropping every result would leave an empty model, which reads
        // downstream as the provider finding nothing sayable -- silence. That is
        // a claim about the speaker sourced entirely from our own parse failure.
        final s = sinkReturning({
          'results': [
            {'transcripts': 'not a list'},
          ],
        });

        await expectLater(s.deliver(chunk(0)), throwsA(isA<FormatException>()));

        expect(s.chunksLost, 1, reason: 'captured, and then genuinely lost');
        expect(s.hasTranscript, isFalse);
      },
    );

    test('a response that CARRIED nothing is silence, not loss', () async {
      // The frozen exhausted-fallback answer: HTTP 200 with `results: []`. It
      // arrived carrying nothing, which is a real answer about the audio rather
      // than a failure to read one, so it must not go the way of the test
      // above.
      final s = sinkReturning({'results': <dynamic>[]});

      await s.deliver(chunk(0));

      expect(s.chunksLost, 0);
      expect(s.hasTranscript, isFalse);
    });

    test('a result that found nothing sayable survives as one', () async {
      // `transcripts: []` is a provider that read the audio and heard nothing.
      // An empty list is not an unreadable list, and collapsing the two would
      // turn this answer into a lost chunk.
      final s = sinkReturning({
        'results': [
          {'transcripts': <dynamic>[]},
        ],
      });

      await s.deliver(chunk(0));

      expect(s.chunksLost, 0);
      expect(s.hasTranscript, isFalse);
    });
  });

  group('the language tag, which comes from a provider', () {
    Future<CallTranscriptSink> sinkSaying(String langCode) async {
      final sink = CallTranscriptSink(
        userL1: 'en',
        userL2: 'es',
        transcribe: (_) async => spokenWord('hola', langCode: langCode),
      );
      await sink.deliver(chunk(0));
      return sink;
    }

    test('a tag with no hyphen cannot be unbounded', () async {
      // The only field in the event that arrives from a provider with no
      // length bound. Splitting on a hyphen trims es-MX to es and does nothing
      // at all to a value with no hyphen in it, so a malformed answer could
      // carry arbitrary text into a half packed against a byte ceiling -- and
      // a half over the ceiling is rejected whole, not trimmed.
      final sink = await sinkSaying('x' * 400);

      expect(sink.langCode, isNull, reason: 'not a language tag, so not used');
    });

    test('a tag the model could not read is no tag at all', () async {
      // The response model reads an unreadable `lang_code` as EMPTY rather than
      // throwing, because a language tag must not cost the words beside it.
      // Empty means unknown there, so writing it out would put a tag on the
      // wire that names no language.
      final sink = await sinkSaying('');

      expect(sink.langCode, isNull);
    });

    test('an ordinary regional tag still yields its primary subtag', () async {
      // The bound must not fire on real input, or every call would lose its
      // language and the field would stop meaning anything.
      final sink = await sinkSaying('es-MX');

      expect(sink.langCode, 'es');
    });
  });
}
