import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_summary_model.dart';
import 'analytics_data/analytics_fixtures.dart';

/// A teacher's summary must not report a word as "used incorrectly" just
/// because the learner never scored on it.
///
/// The counter used to be correct-or-else, which was survivable while every
/// construct in the list had a scored use behind it. Listening exposure breaks
/// that assumption wholesale: hearing a word is 0 XP, so an exposure-only
/// construct has no correct use AND no incorrect one, and the `else` branch
/// filed every word the learner had merely heard under "used incorrectly".
void main() {
  late ServerEventFactory factory;

  setUpAll(() async => factory = await ServerEventFactory.create());
  tearDownAll(() async => factory.dispose());

  final ts = DateTime.utc(2026, 8, 24, 9);

  OneConstructUse use(String lemma, ConstructUseTypeEnum type) =>
      OneConstructUse(
        useType: type,
        lemma: lemma,
        constructType: ConstructTypeEnum.vocab,
        category: 'verb',
        form: lemma,
        xp: type.pointValue,
        metadata: ConstructUseMetaData(roomId: null, timeStamp: ts),
      );

  SpaceAnalyticsSummaryModel summarize(List<OneConstructUse> uses) =>
      SpaceAnalyticsSummaryModel.fromEvents(
        '@learner:example.org',
        [factory.event(uses, ts: ts)],
        {},
        0,
      );

  test('a word the learner only heard is not "used incorrectly"', () {
    final summary = summarize([use('hablar', ConstructUseTypeEnum.hrd)]);

    expect(summary.numLemmasUsedIncorrectly, 0);
    expect(summary.numLemmasUsedCorrectly, 0);
  });

  test('a word the learner got wrong still counts as incorrect', () {
    final summary = summarize([use('hablar', ConstructUseTypeEnum.incPA)]);

    expect(summary.numLemmasUsedIncorrectly, 1);
  });

  test('a word the learner got right still counts as correct', () {
    final summary = summarize([use('hablar', ConstructUseTypeEnum.corPA)]);

    expect(summary.numLemmasUsedCorrectly, 1);
  });

  test('hearing a word the learner already got right changes nothing', () {
    final summary = summarize([
      use('hablar', ConstructUseTypeEnum.corPA),
      use('hablar', ConstructUseTypeEnum.hrd),
    ]);

    expect(summary.numLemmasUsedCorrectly, 1);
    expect(summary.numLemmasUsedIncorrectly, 0);
  });

  test('exposure reaches neither choice counter nor the typed-word count', () {
    final summary = summarize([use('hablar', ConstructUseTypeEnum.hrd)]);

    expect(summary.numChoicesCorrect, 0);
    expect(summary.numChoicesIncorrect, 0);
    expect(summary.numWordsTyped, 0);
  });
}
