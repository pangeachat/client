import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// A new target language starts the map over: the search text and every pill
/// were chosen against the old language's activities, so they go back to their
/// defaults (#9406, world-map.instructions.md "The personalized default").
void main() {
  final spanish = LanguageModel(langCode: 'es', displayName: 'Spanish');
  final french = LanguageModel(langCode: 'fr', displayName: 'French');

  WorldMapFilterState narrowedSpanishMap() {
    final state = WorldMapFilterState()
      ..setL2(spanish)
      ..setQuery('market')
      ..setCefrLevel(LanguageLevelTypeEnum.preA1)
      ..setPartySize(3)
      ..setStatus(ActivityPinState.joinable);
    // The chosen Pre-A1 has no content, so A1 stands in for it.
    state.resolveCefrFallback([
      QuestActivityCard(
        activityId: 'a1-card',
        title: 'a1-card',
        l2: 'es',
        coordinates: const [0, 0],
        learningObjectiveRefs: const [],
        cefr: 'A1',
      ),
    ]);
    return state;
  }

  test('a new target language clears the query and every pill', () {
    final state = narrowedSpanishMap();
    expect(state.filter.canReset, isTrue);
    expect(state.filter.cefrFallback, LanguageLevelTypeEnum.a1);

    state.setL2(french);

    final filter = state.filter;
    expect(filter.l2, french);
    expect(filter.query, isEmpty);
    expect(filter.cefrLevel, isNull);
    expect(filter.cefrFallback, isNull);
    expect(filter.partySize, isNull);
    expect(filter.status, isNull);
    expect(filter.canReset, isFalse);
    expect(filter.activeFilterCount, 0);
  });
}
