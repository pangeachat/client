import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';

/// The practice panel's param (#9438): `practice:vocab` for the learner's
/// usual session, `practice:vocab/<missionId>` for one scoped to a Mission's
/// target vocabulary. The scope rides the URL like every other panel state, so
/// it has to survive a build → parse round trip.
void main() {
  group('AnalyticsPracticeTokenParam', () {
    test('round-trips without a Mission scope', () {
      const param = AnalyticsPracticeTokenParam(
        constructType: ConstructTypeEnum.vocab,
      );
      expect(param.build(), 'vocab');
      expect(AnalyticsPracticeTokenParam.parse(param.build()), param);
      expect(AnalyticsPracticeTokenParam.parse('vocab').missionId, isNull);
    });

    test('round-trips with a Mission scope', () {
      const param = AnalyticsPracticeTokenParam(
        constructType: ConstructTypeEnum.vocab,
        missionId: 'lo-1',
      );
      expect(param.build(), 'vocab/lo-1');
      expect(AnalyticsPracticeTokenParam.parse(param.build()), param);
    });

    test('the scope survives the grammar spelling too', () {
      const param = AnalyticsPracticeTokenParam(
        constructType: ConstructTypeEnum.morph,
        missionId: 'lo-1',
      );
      expect(param.build(), 'grammar/lo-1');
      expect(AnalyticsPracticeTokenParam.parse(param.build()), param);
    });
  });

  group('WorkspaceNav.openPractice with a missionId', () {
    test('seats a Mission-scoped practice token the URL carries', () {
      final loc = WorkspaceNav.openPractice(
        Uri.parse('/'),
        ConstructTypeEnum.vocab,
        missionId: 'lo-1',
      );
      expect(
        parseOpenPanels(Uri.parse(loc)).right.single,
        const AnalyticsPracticePanelToken(
          AnalyticsPracticeTokenParam(
            constructType: ConstructTypeEnum.vocab,
            missionId: 'lo-1',
          ),
        ),
      );
      expect(
        loc,
        anyOf(
          contains('practice:vocab/lo-1'),
          contains('practice:vocab%2Flo-1'),
        ),
      );
    });
  });
}
