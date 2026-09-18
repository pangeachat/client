import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/lemma_usage_chips.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/lemma_use_example_messages.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsDetailsUsageContent extends StatelessWidget {
  final ConstructUses construct;

  const AnalyticsDetailsUsageContent({required this.construct, super.key});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    // Listening exposure sits in memory until the analytics heartbeat drains
    // it, up to five minutes after the playback. Read it through here so the
    // Listening chip moves the moment a playback completes (#8913); the store
    // stays bucketed. The language is the L2 rather than anything on the
    // construct: this page only ever shows the L2's constructs, and the drain
    // files under the same language, so the two reads cannot disagree.
    final buffer = ListeningExposureBuffer.forAccount(client.userID ?? '');
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;
    return ListenableBuilder(
      listenable: Listenable.merge([buffer]),
      builder: (context, _) {
        final pendingHeard = buffer == null || l2 == null
            ? 0
            : buffer.pendingCountFor(construct.id, langCode: l2);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: LemmaUseExampleMessages(
                construct: construct,
                client: client,
              ),
            ),
            ...LearningSkillsEnum.values.where((v) => v.isVisible).map((skill) {
              return LemmaUsageChips(
                construct: construct,
                category: skill,
                tooltip: skill.tooltip(context),
                icon: skill.icon,
                pendingHeard: pendingHeard,
              );
            }),
          ],
        );
      },
    );
  }
}
