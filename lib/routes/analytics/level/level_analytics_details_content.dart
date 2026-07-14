import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/users/level_ribbon.dart';

class LevelAnalyticsDetailsContent extends StatelessWidget {
  final Widget closeButton;
  const LevelAnalyticsDetailsContent({super.key, required this.closeButton});

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final analyticsService = Matrix.of(context).analyticsDataService;
    final language =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    return Scaffold(
      appBar: AppBar(
        leading: Center(child: closeButton),
        title: Text(
          L10n.of(context).level,
          style: FluffyThemes.isColumnMode(context)
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsGeometry.all(16.0),
          child: StreamBuilder(
            stream:
                analyticsService.updateDispatcher.constructUpdateStream.stream,
            builder: (context, _) {
              return Column(
                children: [
                  FutureBuilder(
                    future: language != null
                        ? analyticsService.derivedData(language)
                        : Future.value(DerivedAnalyticsDataModel()),
                    builder: (context, snapshot) {
                      if (snapshot.data == null) {
                        return const SizedBox();
                      }

                      final totalXP = snapshot.data!.totalXP;
                      final maxLevelXP = snapshot.data!.minXPForNextLevel;
                      final level = snapshot.data!.level;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LevelRibbon(height: isColumnMode ? 28.0 : 20.0),
                              const SizedBox(width: 6.0),
                              Text(
                                L10n.of(context).levelShort(level),
                                style: TextStyle(
                                  fontSize: isColumnMode ? 24 : 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppConfig.gold,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            L10n.of(context).xpIntoLevel(totalXP, maxLevelXP),
                            style: TextStyle(
                              fontSize: isColumnMode ? 24 : 16,
                              fontWeight: FontWeight.w900,
                              color: AppConfig.gold,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Expanded(
                    child: FutureBuilder<List<OneConstructUse>>(
                      future: language != null
                          ? analyticsService.getUses(language, count: 100)
                          : Future.value(<OneConstructUse>[]),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator.adaptive(),
                          );
                        }

                        final uses = snapshot.data!;
                        return ListView.builder(
                          itemCount: uses.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return const InstructionsInlineTooltip(
                                instructionsEnum:
                                    InstructionsEnum.levelAnalytics,
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                              );
                            }
                            index--;

                            final use = uses[index];
                            String lemmaCopy = use.lemma;
                            if (use.constructType == ConstructTypeEnum.morph) {
                              debugPrint("Use info: ${use.toJson()}");
                              lemmaCopy =
                                  GrammarConstructsProvider.getTagTitle(
                                    feature: use.category,
                                    tag: use.lemma,
                                  ) ??
                                  use.lemma;
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        width: 40,
                                        alignment: Alignment.centerLeft,
                                        child: Icon(use.useType.icon),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        "\"$lemmaCopy\" - ${use.useType.description(context)}",
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    Container(
                                      alignment: Alignment.topRight,
                                      width: 60,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            "${use.xp > 0 ? '+' : ''}${use.xp}",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 14,
                                              height: 1,
                                              color: use.pointValueColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
