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
/// The animation is driven by [XPGainedEvent.points]. It used to carry the
/// capped per-construct XP delta, which is 0 for a flower-level construct, so
/// answering an exercise on a maxed-out word animated nothing. The event now
/// carries the raw point value of the added uses ([XPGainedEvent.fromUses]),
/// while total XP still uses the capped delta.
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
    test('carries the raw XP of a correct answer', () {
      final event = XPGainedEvent.fromUses([
        use(ConstructUseTypeEnum.corLM),
      ], 'target-id');
      expect(event.points, ConstructUseTypeEnum.corLM.pointValue);
      expect(event.points, greaterThan(0));
      expect(event.targetID, 'target-id');
    });

    test('carries the raw XP of an incorrect answer', () {
      final event = XPGainedEvent.fromUses([
        use(ConstructUseTypeEnum.incLM),
      ], 'target-id');
      expect(event.points, ConstructUseTypeEnum.incLM.pointValue);
      expect(event.points, lessThan(0));
    });

    test('sums the XP of multiple added uses', () {
      final event = XPGainedEvent.fromUses([
        use(ConstructUseTypeEnum.corLM),
        use(ConstructUseTypeEnum.incLM),
      ], null);
      expect(
        event.points,
        ConstructUseTypeEnum.corLM.pointValue +
            ConstructUseTypeEnum.incLM.pointValue,
      );
    });

    test('is nonzero for answers on a flower-level (capped) construct', () {
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

      // The construct's points are capped, so one more use changes the capped
      // total by 0 — the delta the animation used to (wrongly) show.
      expect(construct.points, AnalyticsConstants.xpForFlower);
      final before = construct.points;
      construct.addUses([use(ConstructUseTypeEnum.corLM)]);
      expect(construct.points - before, 0);

      // The event for that same use still animates.
      final event = XPGainedEvent.fromUses([
        use(ConstructUseTypeEnum.corLM),
      ], 'target-id');
      expect(event.points, isNot(0));
    });
  });
}
