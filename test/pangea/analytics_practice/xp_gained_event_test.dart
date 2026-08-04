import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_events.dart';

/// Regression test for #7756: XP gain/loss animations stopped showing on
/// practice exercises whose construct had already reached the flower XP cap.
///
/// The animation used to be driven by [XPGainedEvent.points] — the capped
/// per-construct XP delta, which is 0 for a flower-level construct — so
/// answering an exercise on a maxed-out word animated nothing. The event now
/// also carries [XPGainedEvent.totalPoints], the raw point value of the added
/// uses, which only the animation reads. [XPGainedEvent.points] keeps the
/// capped delta for everything else (total XP / level math).
void main() {
  OneConstructUse use(ConstructUseTypeEnum useType) => OneConstructUse(
    useType: useType,
    lemma: 'gato',
    constructType: ConstructTypeEnum.vocab,
    metadata: ConstructUseMetaData(roomId: null, timeStamp: DateTime.now()),
    category: 'noun',
    form: 'gato',
    xp: useType.pointValue,
  );

  group('XPGainedEvent.fromUses', () {
    test('totalPoints carries the raw XP of a correct answer', () {
      final event = XPGainedEvent.fromUses(
        [use(ConstructUseTypeEnum.corLM)],
        3,
        'target-id',
      );
      expect(event.totalPoints, ConstructUseTypeEnum.corLM.pointValue);
      expect(event.totalPoints, greaterThan(0));
      expect(event.targetID, 'target-id');
    });

    test('totalPoints carries the raw XP of an incorrect answer', () {
      final event = XPGainedEvent.fromUses(
        [use(ConstructUseTypeEnum.incLM)],
        0,
        'target-id',
      );
      expect(event.totalPoints, ConstructUseTypeEnum.incLM.pointValue);
      expect(event.totalPoints, lessThan(0));
    });

    test('totalPoints sums the raw XP of multiple added uses', () {
      final event = XPGainedEvent.fromUses(
        [use(ConstructUseTypeEnum.corLM), use(ConstructUseTypeEnum.incLM)],
        0,
        null,
      );
      expect(
        event.totalPoints,
        ConstructUseTypeEnum.corLM.pointValue +
            ConstructUseTypeEnum.incLM.pointValue,
      );
    });

    test('points keeps the capped delta the caller computed', () {
      final event = XPGainedEvent.fromUses(
        [use(ConstructUseTypeEnum.corLM)],
        0,
        'target-id',
      );
      expect(event.points, 0);
      expect(event.totalPoints, ConstructUseTypeEnum.corLM.pointValue);
    });

    test(
      'totalPoints is nonzero for answers on a flower-level (capped) construct',
      () {
        // Enough correct uses to push the construct past the flower cap.
        final pastCap = List.generate(
          (AnalyticsConstants.xpForFlower ~/
                  ConstructUseTypeEnum.corLM.pointValue) +
              2,
          (_) => use(ConstructUseTypeEnum.corLM),
        );
        final construct = ConstructUses(
          uses: pastCap,
          constructType: ConstructTypeEnum.vocab,
          lemma: 'gato',
          category: 'noun',
        );

        // The construct's points are capped, so one more use changes the
        // capped total by 0 — the delta the animation used to (wrongly) show.
        expect(construct.points, AnalyticsConstants.xpForFlower);
        final before = construct.points;
        construct.addUses([use(ConstructUseTypeEnum.corLM)]);
        final cappedDelta = construct.points - before;
        expect(cappedDelta, 0);

        // The event for that same use still animates via totalPoints.
        final event = XPGainedEvent.fromUses(
          [use(ConstructUseTypeEnum.corLM)],
          cappedDelta,
          'target-id',
        );
        expect(event.points, 0);
        expect(event.totalPoints, isNot(0));
      },
    );
  });
}
