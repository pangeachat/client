import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/repo/quest_repo.dart';

void main() {
  group('QuestRepo.loAtL2Where', () {
    test('selects canonical rows only (#7604)', () {
      final where = QuestRepo.loAtL2Where(['lo-1', 'lo-2'], 'es');
      final clauses = where['and'] as List;

      // activities-v2 is a shared canonical+translation collection; without
      // this clause every translation row of an activity matches too and each
      // renders as its own card/pin. The contract requires `exists`, not
      // equals-null (llm-base-handler-localization.instructions.md).
      expect(
        clauses,
        anyElement(
          equals({
            'req.source_request_hash': {'exists': false},
          }),
        ),
      );
    });

    test('keeps the LO and l2 constraints', () {
      final where = QuestRepo.loAtL2Where(['lo-1'], 'es');
      final clauses = where['and'] as List;
      expect(
        clauses,
        anyElement(
          equals({
            'or': [
              {
                'learningObjectiveRefs': {'contains': 'lo-1'},
              },
            ],
          }),
        ),
      );
      expect(
        clauses,
        anyElement(
          equals({
            'res.plan.l2': {'equals': 'es'},
          }),
        ),
      );
    });
  });

  group('QuestRepo.dedupeByActivityId', () {
    test('keeps the first row per activity_id', () {
      final rows = [
        (id: 'a', tag: 1),
        (id: 'b', tag: 2),
        (id: 'a', tag: 3),
        (id: 'c', tag: 4),
        (id: 'b', tag: 5),
      ];
      final unique = QuestRepo.dedupeByActivityId(rows, (r) => r.id);
      expect(unique.map((r) => r.tag), [1, 2, 4]);
    });

    test('passes unique rows through unchanged', () {
      final rows = [(id: 'a'), (id: 'b')];
      expect(QuestRepo.dedupeByActivityId(rows, (r) => r.id), rows);
    });
  });
}
