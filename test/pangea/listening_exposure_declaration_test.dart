import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';
import 'package:fluffychat/features/analytics/listening_exposure_declaration.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';

/// Every read-aloud path declares what it is about to say. The declaration is
/// the only thing standing between "this surface plays L2 audio" and "this
/// lemma was heard", so what it filters and what it refuses to guess matters.
void main() {
  PangeaToken token(String form, String lemma, {required bool saveVocab}) =>
      PangeaToken(
        text: PangeaTokenText(content: form, offset: 0, length: form.length),
        lemma: Lemma(text: lemma, form: form, saveVocab: saveVocab),
        pos: 'VERB',
        morph: const {},
      );

  setUp(ListeningExposureBuffer.debugResetAccounts);

  group('ofTokens', () {
    test('declares the lemma, not the surface form', () {
      // A bucket is keyed on the construct, so a declaration that leaked the
      // inflected form would file "hablando" and "hablo" under two words.
      final declaration = ListeningExposureDeclaration.ofTokens(
        langCode: 'es',
        [token('hablando', 'hablar', saveVocab: true)],
      );

      expect(declaration.constructs.single.lemma, 'hablar');
      expect(declaration.constructs.single.type, ConstructTypeEnum.vocab);
    });

    test('drops tokens the rest of analytics ignores', () {
      // saveVocab is the same gate every other lemma-level signal applies. A
      // word that is invisible everywhere else must not become visible only
      // because it was read aloud.
      final declaration = ListeningExposureDeclaration.ofTokens(
        langCode: 'es',
        [
          token('hablar', 'hablar', saveVocab: true),
          token('de', 'de', saveVocab: false),
        ],
      );

      expect(declaration.constructs.map((c) => c.lemma), ['hablar']);
    });

    test('a message of nothing but ignorable tokens declares nothing', () {
      final declaration = ListeningExposureDeclaration.ofTokens(
        langCode: 'es',
        [token('de', 'de', saveVocab: false)],
      );

      expect(declaration.constructs, isEmpty);
    });
  });

  group('recording', () {
    ConstructIdentifier id(String lemma) => ConstructIdentifier(
      lemma: lemma,
      type: ConstructTypeEnum.vocab,
      category: 'verb',
    );

    test('banks one exposure per declared construct', () {
      ListeningExposureDeclaration([
        id('hablar'),
        id('comer'),
      ], langCode: 'es').record('@learner:server');

      final drained = ListeningExposureBuffer.forAccount(
        '@learner:server',
      )!.drain('es');

      expect(drained.map((u) => u.lemma), containsAll(['hablar', 'comer']));
      expect(
        drained.every((u) => u.useType == ConstructUseTypeEnum.hrd),
        isTrue,
      );
    });

    test('an exempt path banks nothing', () {
      const ListeningExposureDeclaration.exempt(
        'speaks no L2 lemma',
      ).record('@learner:server');

      expect(
        ListeningExposureBuffer.forAccount('@learner:server')!.pendingExposures,
        0,
      );
    });

    test('an unknown account banks nothing rather than guessing', () {
      // Attributing a hearing to the wrong account is worse than losing it.
      ListeningExposureDeclaration([id('hablar')], langCode: 'es').record(null);

      expect(ListeningExposureBuffer.forAccount(''), isNull);
    });

    test('repeated plays are not deduplicated', () {
      // Repetition IS the variable this feature exists to measure: collapsing
      // replays would encode a theory nobody asked for.
      final declaration = ListeningExposureDeclaration([
        id('hablar'),
      ], langCode: 'es');

      declaration.record('@learner:server');
      declaration.record('@learner:server');

      expect(
        ListeningExposureBuffer.forAccount(
          '@learner:server',
        )!.drain('es').single.count,
        2,
      );
    });
  });

  group('the wire format', () {
    OneConstructUse use({int count = 1}) => OneConstructUse(
      useType: ConstructUseTypeEnum.hrd,
      lemma: 'hablar',
      constructType: ConstructTypeEnum.vocab,
      category: 'verb',
      form: null,
      xp: 0,
      count: count,
      metadata: ConstructUseMetaData(
        roomId: null,
        eventId: null,
        timeStamp: DateTime.utc(2026, 8, 24, 9),
      ),
    );

    test('sends the count explicitly, never implying it by row', () {
      // The ingest reads named keys, so a count that only existed as "how many
      // rows are there" would arrive as one.
      expect(use(count: 7).toJson()['count'], 7);
    });

    test('round-trips', () {
      expect(OneConstructUse.fromJson(use(count: 7).toJson()).count, 7);
    });

    test('a row written before bucketing existed counts as one', () {
      final legacy = use().toJson()..remove('count');

      expect(OneConstructUse.fromJson(legacy).count, 1);
    });

    test('every other use type still means one occurrence', () {
      final click = OneConstructUse(
        useType: ConstructUseTypeEnum.click,
        lemma: 'hablar',
        constructType: ConstructTypeEnum.vocab,
        category: 'verb',
        form: 'hablar',
        xp: ConstructUseTypeEnum.click.pointValue,
        metadata: ConstructUseMetaData(
          roomId: '!r:server',
          timeStamp: DateTime.utc(2026, 8, 24, 9),
        ),
      );

      expect(click.count, 1);
    });
  });

  group('classification', () {
    test('is listening', () {
      expect(
        ConstructUseTypeEnum.hrd.skillsEnumType.name,
        ConstructUseTypeEnum.corLA.skillsEnumType.name,
      );
    });

    test('is not something the learner produced', () {
      expect(ConstructUseTypeEnum.hrd.sentByUser, isFalse);
    });

    test('lands in no summary bucket', () {
      // Neither correct nor incorrect, and not a typed word.
      expect(ConstructUseTypeEnum.hrd.summaryEnumType, isNull);
    });

    test('does not read as chat production or a wrong answer', () {
      expect(ConstructUseTypeEnum.hrd.isChatUse, isFalse);
      expect(ConstructUseTypeEnum.hrd.isIncorrectPractice, isFalse);
    });

    test('an older client reads it as an unclassified use, not as noise', () {
      // Old clients map an unknown value to `nan`, which is invisible on the
      // details page rather than mis-drawn.
      expect(ConstructUseTypeEnum.fromString('hrd'), ConstructUseTypeEnum.hrd);
      expect(
        ConstructUseTypeEnum.fromString('someFutureType'),
        ConstructUseTypeEnum.nan,
      );
    });
  });
}
