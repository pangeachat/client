import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The scope-dependence of the candidate filter (#7716). A selected course
/// narrows WHICH activities compete, not whether the learner can search or
/// filter within them (world-map.instructions.md, "Filters") — so the pills and
/// the query apply in both scopes. The one term that does not is the
/// settings-fixed language: course pins are fetched at the COURSE's own L2, so
/// applying the learner's settings L2 there would empty the map of a course
/// taught in another language, with no lever to widen.
QuestActivityCard _card(
  String id, {
  String l2 = 'es',
  String cefr = 'A2',
  int? roleCount,
  String? title,
}) => QuestActivityCard(
  activityId: id,
  title: title ?? id,
  l2: l2,
  coordinates: null,
  learningObjectiveRefs: const [],
  cefr: cefr,
  roleCount: roleCount,
);

void main() {
  final spanish = LanguageModel(langCode: 'es', displayName: 'Spanish');

  WorldMapFilterState stateWithL2() => WorldMapFilterState()..setL2(spanish);

  group('the language constant is scope-dependent', () {
    test('world scope drops a pin outside the settings L2', () {
      final filter = stateWithL2();
      expect(
        filter.include(_card('a', l2: 'fr'), ActivityPinState.available),
        isFalse,
      );
    });

    test('course scope keeps it — the course owns the language', () {
      final filter = stateWithL2();
      expect(
        filter.include(
          _card('a', l2: 'fr'),
          ActivityPinState.available,
          applyLanguage: false,
        ),
        isTrue,
      );
    });

    test('matchesIgnoringPills follows the same scope rule', () {
      final filter = stateWithL2();
      final offLanguage = _card('a', l2: 'fr');
      expect(filter.matchesIgnoringPills(offLanguage), isFalse);
      expect(
        filter.matchesIgnoringPills(offLanguage, applyLanguage: false),
        isTrue,
      );
    });
  });

  group('the pills and query still narrow a course scope', () {
    test('the Level pill excludes an off-level pin', () {
      final filter = stateWithL2()..setCefrLevel(LanguageLevelTypeEnum.b2);
      expect(
        filter.include(
          _card('a', l2: 'fr', cefr: 'A2'),
          ActivityPinState.available,
          applyLanguage: false,
        ),
        isFalse,
      );
    });

    test('the Party size pill matches the designed role count exactly', () {
      final filter = stateWithL2()..setPartySize(3);
      bool includes(int roles) => filter.include(
        _card('a', roleCount: roles),
        ActivityPinState.available,
        applyLanguage: false,
      );
      expect(includes(3), isTrue);
      expect(includes(4), isFalse);
    });

    test('the Status pill matches the resolved pin state', () {
      final filter = stateWithL2()..setStatus(ActivityPinState.joinable);
      expect(
        filter.include(
          _card('a'),
          ActivityPinState.joinable,
          applyLanguage: false,
        ),
        isTrue,
      );
      expect(
        filter.include(
          _card('a'),
          ActivityPinState.available,
          applyLanguage: false,
        ),
        isFalse,
      );
    });

    test('the free-text query narrows on the card text', () {
      final filter = stateWithL2()..setQuery('market');
      bool includes(String title) => filter.include(
        _card('a', title: title),
        ActivityPinState.available,
        applyLanguage: false,
      );
      expect(includes('At the market'), isTrue);
      expect(includes('At the airport'), isFalse);
    });
  });
}
