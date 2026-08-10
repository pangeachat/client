import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'get_test_client.dart';

/// #8210 — token-info-feedback corrections as atomic correction
/// representations.
///
/// Write side: `buildTokenCorrection` (the pure builder behind
/// `sendTokenCorrection`) marks the rep `isCorrection` and embeds the tokens
/// in its content. Read side: `correctedSent` / `pickRepresentationByLanguage`
/// prefer a token-rich correction over the stale embedded original — the fix
/// for corrections silently dropped on received messages — while
/// `originalSent` keeps reporting what the sender actually produced.
///
/// The read-path tests feed the exact `toJson` output of the builder through
/// a timeline rep event, so the write and read paths are tested against each
/// other with no network.

PangeaToken _token(String content, int offset) => PangeaToken.fromJson({
  'text': {'content': content, 'offset': offset, 'length': content.length},
  'lemma': {'text': content, 'save_vocab': true, 'form': content},
  'pos': 'NOUN',
  'morph': <String, dynamic>{},
});

/// The mis-tokenized shape from the issue: the whole phrase as ONE token.
PangeaMessageTokens _hugeTokenEmbed() => PangeaMessageTokens(
  tokens: [_token('buenosdías', 0)],
  detections: const [LanguageDetectionModel(langCode: 'es', confidence: 1)],
);

/// The corrected shape: the phrase split into individual words.
PangeaMessageTokens _splitTokens({String langCode = 'es'}) =>
    PangeaMessageTokens(
      tokens: [_token('buenos', 0), _token('días', 7)],
      detections: [LanguageDetectionModel(langCode: langCode, confidence: 1)],
    );

void main() {
  group('PangeaRepresentation wire format', () {
    test('round-trips isCorrection and embedded tokens', () {
      final rep = PangeaRepresentation(
        langCode: 'es',
        text: 'buenos días',
        originalSent: false,
        originalWritten: false,
        isCorrection: true,
        tokens: _splitTokens(),
      );

      final parsed = PangeaRepresentation.fromJson(rep.toJson());
      expect(parsed.isCorrection, isTrue);
      expect(parsed.tokens, isNotNull);
      expect(parsed.tokens!.tokens.map((t) => t.text.content), [
        'buenos',
        'días',
      ]);
      expect(parsed.tokens!.detections?.first.langCode, 'es');
    });

    test('legacy json without the new keys parses as a non-correction', () {
      final parsed = PangeaRepresentation.fromJson({
        'txt': 'buenos días',
        'lang': 'es',
      });
      expect(parsed.isCorrection, isFalse);
      expect(parsed.tokens, isNull);
    });

    test('toJson omits the new keys on a non-correction (legacy shape '
        'byte-stable)', () {
      final json = PangeaRepresentation(
        langCode: 'es',
        text: 'buenos días',
        originalSent: true,
        originalWritten: false,
      ).toJson();
      expect(json.containsKey('crctn'), isFalse);
      expect(json.containsKey('tkns'), isFalse);
    });
  });

  group('with a live timeline', () {
    late Client client;
    late Room room;
    late Timeline timeline;
    late PangeaMessageEvent message;

    const messageEventId = r'$msg:fakeServer.notExisting';

    setUp(() async {
      client = await getTestClient();
      room = Room(id: '!chat:fakeServer.notExisting', client: client);
      timeline = await room.getTimeline();
      // A RECEIVED text message (sender != the test client's user) whose
      // embedded tokensSent carries the mis-tokenized single huge token.
      message = PangeaMessageEvent(
        event: Event(
          type: EventTypes.Message,
          eventId: messageEventId,
          senderId: '@othertest:fakeServer.notExisting',
          originServerTs: DateTime.now(),
          content: {
            'msgtype': 'm.text',
            'body': 'buenosdías',
            MessageConstants.tokensSent: _hugeTokenEmbed().toJson(),
          },
          room: room,
        ),
        timeline: timeline,
        ownMessage: false,
      );
    });

    tearDown(() async {
      timeline.cancelSubscriptions();
      await client.dispose();
    });

    /// A correction rep event whose content is EXACTLY what the write path
    /// produces (`buildTokenCorrection(...).toJson()`).
    Event correctionEvent(
      String eventId,
      DateTime ts, {
      PangeaMessageTokens? tokensSent,
      String text = 'buenosdías',
    }) => Event(
      type: PangeaEventTypes.representation,
      eventId: eventId,
      senderId: client.userID!,
      originServerTs: ts,
      content: {
        PangeaEventTypes.representation: PangeaMessageEvent.buildTokenCorrection(
          fullText: text,
          tokensSent: tokensSent ?? _splitTokens(),
          fallbackLangCode: 'es',
        ).toJson(),
      },
      room: room,
    );

    void inject(List<Event> repEvents) {
      timeline.aggregatedEvents[messageEventId] = {
        PangeaEventTypes.representation: repEvents.toSet(),
      };
    }

    test('without a correction, correctedSent falls back to originalSent', () {
      expect(message.originalSent, isNotNull);
      expect(message.correctedSent, same(message.originalSent));
      expect(message.correctedSent!.tokens!.map((t) => t.text.content), [
        'buenosdías',
      ]);
    });

    test('a token-rich correction wins over the stale embed on a RECEIVED '
        'message; originalSent still reports what the sender produced', () {
      inject([correctionEvent(r'$corr:s', DateTime.now())]);

      // Teeth: before #8210 the correction (an m.replace by a third party)
      // was discarded and the huge token stayed the only readable shape.
      expect(message.correctedSent!.tokens!.map((t) => t.text.content), [
        'buenos',
        'días',
      ]);
      expect(message.correctedSent!.event?.eventId, r'$corr:s');

      // Provenance is untouched: analytics/choreo consumers still see the
      // sender's actual production through originalSent.
      expect(message.originalSent!.tokens!.map((t) => t.text.content), [
        'buenosdías',
      ]);
    });

    test('a correction WITHOUT usable tokens is ignored (a partial correction '
        'can never override a token-rich original)', () {
      inject([
        correctionEvent(
          r'$corr-empty:s',
          DateTime.now(),
          tokensSent: PangeaMessageTokens(tokens: []),
        ),
      ]);

      expect(message.correctedSent, same(message.originalSent));
    });

    test('with two corrections, the NEWEST wins', () {
      final now = DateTime.now();
      inject([
        correctionEvent(
          r'$corr-old:s',
          now.subtract(const Duration(minutes: 1)),
        ),
        correctionEvent(
          r'$corr-new:s',
          now,
          tokensSent: PangeaMessageTokens(
            tokens: [_token('buenos', 0), _token('día', 7), _token('s', 10)],
            detections: const [
              LanguageDetectionModel(langCode: 'es', confidence: 1),
            ],
          ),
        ),
      ]);

      expect(message.correctedSent!.event?.eventId, r'$corr-new:s');
      expect(message.correctedSent!.tokens, hasLength(3));
    });

    test('a language-update correction changes correctedSent.langCode', () {
      inject([
        correctionEvent(
          r'$corr-lang:s',
          DateTime.now(),
          tokensSent: _splitTokens(langCode: 'pt'),
        ),
      ]);

      expect(message.originalSent!.langCode, 'es');
      expect(message.correctedSent!.langCode, 'pt');
    });

    group('RepresentationEvent token sourcing', () {
      test('content-embedded tokens win over a child tokens event', () {
        final correction = correctionEvent(r'$corr2:s', DateTime.now());
        inject([correction]);
        // A stale child tokens event under the correction: embedded must win.
        timeline.aggregatedEvents[correction.eventId] = {
          PangeaEventTypes.tokens: {
            Event(
              type: PangeaEventTypes.tokens,
              eventId: r'$childtokens:s',
              senderId: client.userID!,
              originServerTs: DateTime.now(),
              content: {
                PangeaEventTypes.tokens: PangeaMessageTokens(
                  tokens: [_token('stale', 0)],
                ).toJson(),
              },
              room: room,
            ),
          },
        };

        expect(message.correctedSent!.tokens!.map((t) => t.text.content), [
          'buenos',
          'días',
        ]);
      });

      test('a rep without embedded tokens still reads its child tokens event '
          '(pre-correction path intact)', () {
        final plainRep = Event(
          type: PangeaEventTypes.representation,
          eventId: r'$plainrep:s',
          senderId: client.userID!,
          originServerTs: DateTime.now(),
          content: {
            PangeaEventTypes.representation: PangeaRepresentation(
              langCode: 'en',
              text: 'good morning',
              originalSent: false,
              originalWritten: false,
            ).toJson(),
          },
          room: room,
        );
        inject([plainRep]);
        timeline.aggregatedEvents[plainRep.eventId] = {
          PangeaEventTypes.tokens: {
            Event(
              type: PangeaEventTypes.tokens,
              eventId: r'$childtokens2:s',
              senderId: client.userID!,
              originServerTs: DateTime.now(),
              content: {
                PangeaEventTypes.tokens: PangeaMessageTokens(
                  tokens: [_token('good', 0), _token('morning', 5)],
                ).toJson(),
              },
              room: room,
            ),
          },
        };

        final rep = message.representations.firstWhere(
          (r) => r.event?.eventId == r'$plainrep:s',
        );
        expect(rep.tokens!.map((t) => t.text.content), ['good', 'morning']);
      });
    });

    group('pickRepresentationByLanguage', () {
      test('preferCorrection: a same-language token-rich correction beats the '
          'earlier embed match', () {
        inject([correctionEvent(r'$corr3:s', DateTime.now())]);
        final picked = PangeaMessageEvent.pickRepresentationByLanguage(
          message.representations,
          'es',
          preferCorrection: true,
        );
        expect(picked?.event?.eventId, r'$corr3:s');
      });

      test('a correction in a DIFFERENT language never hijacks the display '
          'match', () {
        inject([
          correctionEvent(
            r'$corr-fr:s',
            DateTime.now(),
            tokensSent: _splitTokens(langCode: 'fr'),
          ),
        ]);
        final picked = PangeaMessageEvent.pickRepresentationByLanguage(
          message.representations,
          'es',
          preferCorrection: true,
        );
        // The es-language match is still the embedded original.
        expect(picked, same(message.originalSent));
      });

      test('without preferCorrection the embed keeps winning (legacy display '
          'behavior)', () {
        inject([correctionEvent(r'$corr4:s', DateTime.now())]);
        final picked = PangeaMessageEvent.pickRepresentationByLanguage(
          message.representations,
          'es',
        );
        expect(picked, same(message.originalSent));
      });
    });
  });

  group('buildTokenCorrection', () {
    test('marks the rep a correction and embeds the tokens', () {
      final rep = PangeaMessageEvent.buildTokenCorrection(
        fullText: 'buenosdías',
        tokensSent: _splitTokens(),
      );
      expect(rep.isCorrection, isTrue);
      expect(rep.originalSent, isFalse);
      expect(rep.originalWritten, isFalse);
      expect(rep.text, 'buenosdías');
      expect(rep.tokens!.tokens, hasLength(2));
    });

    test('langCode comes from the correction detections first', () {
      final rep = PangeaMessageEvent.buildTokenCorrection(
        fullText: 'bom dia',
        tokensSent: _splitTokens(langCode: 'pt'),
        fallbackLangCode: 'es',
      );
      expect(rep.langCode, 'pt');
    });

    test('falls back to fallbackLangCode, then unknown', () {
      final noDetections = PangeaMessageTokens(tokens: [_token('hola', 0)]);
      expect(
        PangeaMessageEvent.buildTokenCorrection(
          fullText: 'hola',
          tokensSent: noDetections,
          fallbackLangCode: 'es',
        ).langCode,
        'es',
      );
      expect(
        PangeaMessageEvent.buildTokenCorrection(
          fullText: 'hola',
          tokensSent: noDetections,
        ).langCode,
        'unk',
      );
    });
  });
}
