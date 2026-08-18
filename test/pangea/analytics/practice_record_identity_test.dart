import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_record.dart';

/// The practice record's direct `cId ==` lookups under strict identifier
/// equality (#8441): a response recorded for a token's construct is found by
/// the same construct; a legacy response stored without a category ('other')
/// no longer matches a categorised target.
void main() {
  ConstructIdentifier id(String lemma, String category) => ConstructIdentifier(
    lemma: lemma,
    type: ConstructTypeEnum.vocab,
    category: category,
  );

  PracticeExerciseRecordResponse response(
    ConstructIdentifier cId,
    String text,
  ) => PracticeExerciseRecordResponse(
    cId: cId,
    text: text,
    score: 1,
    timestamp: DateTime.utc(2026, 1, 1),
  );

  test('same construct (case-insensitive category) matches', () {
    final record = PracticeRecord(
      responses: [response(id('perro', 'noun'), 'dog')],
    );
    expect(record.alreadyHasMatchResponse(id('perro', 'noun'), 'dog'), isTrue);
    expect(record.alreadyHasMatchResponse(id('perro', 'NOUN'), 'dog'), isTrue);
    expect(record.alreadyHasMatchResponse(id('perro', 'noun'), 'cat'), isFalse);
    expect(record.alreadyHasMatchResponse(id('gato', 'noun'), 'dog'), isFalse);
  });

  test('other-category response does not match a categorised construct', () {
    final record = PracticeRecord(
      responses: [response(id('perro', ''), 'dog')],
    );
    expect(record.alreadyHasMatchResponse(id('perro', 'noun'), 'dog'), isFalse);
    expect(record.alreadyHasMatchResponse(id('perro', 'other'), 'dog'), isTrue);
  });

  test('response equality follows identifier equality', () {
    final a = response(id('perro', 'noun'), 'dog');
    final b = response(id('perro', 'noun'), 'dog');
    final c = response(id('perro', 'other'), 'dog');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
  });
}
