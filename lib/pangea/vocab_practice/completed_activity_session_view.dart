import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/level_up/star_rain_widget.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/vocab_practice/percent_marker_bar.dart';
import 'package:fluffychat/pangea/vocab_practice/stat_card.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_page.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CompletedActivitySessionView extends StatelessWidget {
  final VocabPracticeState controller;
  const CompletedActivitySessionView(this.controller, {super.key});

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final username =
        Matrix.of(context).client.userID?.split(':').first.substring(1) ?? '';
    final bool accuracyAchievement =
        controller.sessionLoader.value!.accuracy == 100;
    final bool timeAchievement =
        controller.sessionLoader.value!.elapsedSeconds <= 60;
    final int numBonusPoints = controller.sessionLoader.value!.completedUses
        .where((use) => use.xp > 0)
        .length;
    //give double bonus for both, single for one, none for zero
    final int bonusXp = (accuracyAchievement && timeAchievement)
        ? numBonusPoints * 2
        : (accuracyAchievement || timeAchievement)
            ? numBonusPoints
            : 0;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16, right: 16, left: 16),
          child: Column(
            children: [
              Text(
                L10n.of(context).congratulationsYouveCompletedPractice,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: FutureBuilder(
                        future: Matrix.of(context).client.fetchOwnProfile(),
                        builder: (context, snapshot) {
                          final avatarUrl = snapshot.data?.avatarUrl;
                          return Avatar(
                            name: username,
                            showPresence: false,
                            size: 100,
                            mxContent: avatarUrl,
                            userId: Matrix.of(context).client.userID,
                          );
                        },
                      ),
                    ),
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 16.0,
                            bottom: 16.0,
                          ),
                          child: FutureBuilder(
                            future: controller.derivedAnalyticsData,
                            builder: (context, snapshot) => AnimatedProgressBar(
                              height: 20.0,
                              widthPercent: snapshot.hasData
                                  ? snapshot.data!.levelProgress
                                  : 0.0,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              duration: const Duration(milliseconds: 500),
                            ),
                          ),
                        ),
                        Text(
                          "+ ${controller.sessionLoader.value!.totalXpGained + bonusXp} XP",
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: AppConfig.goldLight,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    StatCard(
                      icon: Icons.my_location,
                      text:
                          "${L10n.of(context).accuracy}: ${controller.sessionLoader.value!.accuracy}%",
                      isAchievement: accuracyAchievement,
                      achievementText: "+ $numBonusPoints XP",
                      child: PercentMarkerBar(
                        height: 20.0,
                        widthPercent:
                            controller.sessionLoader.value!.accuracy / 100.0,
                        markerWidth: 20.0,
                        markerColor: AppConfig.success,
                        backgroundColor:
                            !(controller.sessionLoader.value!.accuracy == 100)
                                ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                : Color.alphaBlend(
                                    AppConfig.goldLight.withValues(alpha: 0.3),
                                    Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                      ),
                    ),
                    StatCard(
                      icon: Icons.alarm,
                      text:
                          "${L10n.of(context).time}: ${_formatTime(controller.sessionLoader.value!.elapsedSeconds)}",
                      isAchievement: timeAchievement,
                      achievementText: "+ $numBonusPoints XP",
                      child: TimeStarsWidget(
                        elapsedSeconds:
                            controller.sessionLoader.value!.elapsedSeconds,
                        timeForBonus:
                            controller.sessionLoader.value!.timeForBonus,
                      ),
                    ),
                    Column(
                      children: [
                        //expanded row button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 8.0,
                            ),
                          ),
                          onPressed: () => controller.reloadSession(),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                L10n.of(context).anotherRound,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 8.0,
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                L10n.of(context).quit,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const StarRainWidget(
          showBlast: true,
          rainDuration: Duration(seconds: 5),
        ),
      ],
    );
  }
}

class TimeStarsWidget extends StatelessWidget {
  final int elapsedSeconds;
  final int timeForBonus;

  const TimeStarsWidget({
    required this.elapsedSeconds,
    required this.timeForBonus,
    super.key,
  });

  int get starCount {
    if (elapsedSeconds <= timeForBonus) return 5;
    if (elapsedSeconds <= timeForBonus * 1.5) return 4;
    if (elapsedSeconds <= timeForBonus * 2) return 3;
    if (elapsedSeconds <= timeForBonus * 2.5) return 2;
    return 1; // anything above 2.5x timeForBonus
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        5,
        (index) => Icon(
          index < starCount ? Icons.star : Icons.star_outline,
          color: AppConfig.goldLight,
          size: 36,
        ),
      ),
    );
  }
}
