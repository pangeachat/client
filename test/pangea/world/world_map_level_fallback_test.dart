import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_level_fallback_notice.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Empty levels fall back to the nearest level that has content, and the map
/// SAYS so (#8401, world-map.instructions.md "Empty levels fall back to the
/// nearest one with content"). The catalog carries no Pre-A1 (nor C1/C2)
/// activity in any language, so picking one of those levels used to empty the
/// map and dead-end on "widen the search" — which drops every other pill too.
QuestActivityCard _card(
  String id, {
  String l2 = 'es',
  String? cefr = 'A1',
  List<double>? coordinates = const [0, 0],
}) => QuestActivityCard(
  activityId: id,
  title: id,
  l2: l2,
  coordinates: coordinates,
  learningObjectiveRefs: const [],
  cefr: cefr,
);

void main() {
  final spanish = LanguageModel(langCode: 'es', displayName: 'Spanish');

  WorldMapFilterState stateWithL2() => WorldMapFilterState()..setL2(spanish);

  group('nearestTo', () {
    test('returns null when the chosen level has content', () {
      expect(
        LanguageLevelTypeEnum.nearestTo(LanguageLevelTypeEnum.a1, {
          LanguageLevelTypeEnum.a1,
          LanguageLevelTypeEnum.b1,
        }),
        isNull,
      );
    });

    test('returns null when there is nothing to fall back to', () {
      expect(
        LanguageLevelTypeEnum.nearestTo(LanguageLevelTypeEnum.preA1, {}),
        isNull,
      );
    });

    test('picks the closest level by distance', () {
      expect(
        LanguageLevelTypeEnum.nearestTo(LanguageLevelTypeEnum.preA1, {
          LanguageLevelTypeEnum.a1,
          LanguageLevelTypeEnum.b2,
        }),
        LanguageLevelTypeEnum.a1,
      );
      expect(
        LanguageLevelTypeEnum.nearestTo(LanguageLevelTypeEnum.c2, {
          LanguageLevelTypeEnum.a1,
          LanguageLevelTypeEnum.b2,
        }),
        LanguageLevelTypeEnum.b2,
      );
    });

    test('a tie resolves downward — the easier level wins', () {
      expect(
        LanguageLevelTypeEnum.nearestTo(LanguageLevelTypeEnum.b1, {
          LanguageLevelTypeEnum.a2,
          LanguageLevelTypeEnum.b2,
        }),
        LanguageLevelTypeEnum.a2,
      );
    });
  });

  group('resolveCefrFallback', () {
    test('Pre-A1 with only A1 content falls back to A1 and matches it', () {
      final filter = stateWithL2()..setCefrLevel(LanguageLevelTypeEnum.preA1);
      final loaded = [_card('a'), _card('b')];

      expect(
        filter.include(loaded.first, ActivityPinState.available),
        isFalse,
        reason: 'before resolution the chosen level is honoured exactly',
      );

      expect(filter.resolveCefrFallback(loaded), isTrue);
      expect(filter.filter.cefrFallback, LanguageLevelTypeEnum.a1);
      expect(filter.filter.cefrLevel, LanguageLevelTypeEnum.preA1);
      expect(filter.include(loaded.first, ActivityPinState.available), isTrue);
    });

    test('a level that HAS content is honoured exactly — no fallback', () {
      final filter = stateWithL2()..setCefrLevel(LanguageLevelTypeEnum.a1);
      expect(filter.resolveCefrFallback([_card('a')]), isFalse);
      expect(filter.filter.cefrFallback, isNull);
      expect(
        filter.include(_card('b', cefr: 'B2'), ActivityPinState.available),
        isFalse,
        reason: 'an honoured level still excludes every other level',
      );
    });

    test('an unleveled card satisfies any choice, so nothing stands in', () {
      final filter = stateWithL2()..setCefrLevel(LanguageLevelTypeEnum.preA1);
      expect(filter.resolveCefrFallback([_card('a', cefr: null)]), isFalse);
      expect(filter.filter.cefrFallback, isNull);
    });

    test('"All levels" never falls back', () {
      final filter = stateWithL2();
      expect(filter.resolveCefrFallback([_card('a')]), isFalse);
      expect(filter.filter.cefrFallback, isNull);
    });

    test(
      'an empty candidate set leaves the choice alone for the empty card',
      () {
        final filter = stateWithL2()..setCefrLevel(LanguageLevelTypeEnum.preA1);
        expect(filter.resolveCefrFallback(const []), isFalse);
        expect(filter.filter.cefrFallback, isNull);
      },
    );

    test('re-picking a level drops the previous fallback', () {
      final filter = stateWithL2()..setCefrLevel(LanguageLevelTypeEnum.preA1);
      filter.resolveCefrFallback([_card('a')]);
      expect(filter.filter.cefrFallback, LanguageLevelTypeEnum.a1);

      filter.setCefrLevel(LanguageLevelTypeEnum.b1);
      expect(filter.filter.cefrFallback, isNull);
    });

    test('reset clears the fallback with the pills', () {
      final filter = stateWithL2()..setCefrLevel(LanguageLevelTypeEnum.preA1);
      filter.resolveCefrFallback([_card('a')]);
      filter.resetFilters();
      expect(filter.filter.cefrFallback, isNull);
      expect(filter.filter.cefrLevel, isNull);
    });

    test('an unrecognised level code contributes nothing to the choices', () {
      final filter = stateWithL2()..setCefrLevel(LanguageLevelTypeEnum.preA1);
      // Would silently parse to A1 through LanguageLevelTypeEnum.fromString.
      expect(filter.resolveCefrFallback([_card('a', cefr: 'ZZ')]), isFalse);
      expect(filter.filter.cefrFallback, isNull);
    });
  });

  group('the notice', () {
    Future<void> pump(
      WidgetTester tester, {
      LanguageLevelTypeEnum? selected,
      LanguageLevelTypeEnum? fallback,
    }) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: WorldMapLevelFallbackNotice(
            selected: selected,
            fallback: fallback,
          ),
        ),
      ),
    );

    testWidgets('names both the level asked for and the one shown', (
      tester,
    ) async {
      await pump(
        tester,
        selected: LanguageLevelTypeEnum.preA1,
        fallback: LanguageLevelTypeEnum.a1,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No Pre-A1 activities yet — showing A1 instead.'),
        findsOneWidget,
      );
    });

    testWidgets('draws nothing without a fallback in force', (tester) async {
      await pump(tester, selected: LanguageLevelTypeEnum.a1);
      await tester.pumpAndSettle();
      expect(find.byType(Text), findsNothing);
    });
  });
}
