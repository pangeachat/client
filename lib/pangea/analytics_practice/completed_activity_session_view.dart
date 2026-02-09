import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/level_up/star_rain_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/analytics_practice/percent_marker_bar.dart';
import 'package:fluffychat/pangea/analytics_practice/stat_card.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CompletedActivitySessionView extends StatelessWidget {
  final AnalyticsPracticeSessionModel session;
  final AnalyticsPracticeState controller;
  const CompletedActivitySessionView(
    this.session,
    this.controller, {
    super.key,
  });

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final username =
        Matrix.of(context).client.userID?.split(':').first.substring(1) ?? '';

    final double accuracy = session.state.accuracy;
    final int elapsedSeconds = session.state.elapsedSeconds;

    final bool accuracyAchievement = accuracy == 100;
    final bool timeAchievement = elapsedSeconds <= 60;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16, right: 16, left: 16),
          child: Column(
            children: [
              Text(
                controller.getCompletionMessage(context),
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
                          "+ ${session.state.allXPGained} XP",
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
                      text: "${L10n.of(context).accuracy}: $accuracy%",
                      isAchievement: accuracyAchievement,
                      achievementText: "+ ${session.state.accuracyBonusXP} XP",
                      child: PercentMarkerBar(
                        height: 20.0,
                        widthPercent: accuracy / 100.0,
                        markerWidth: 20.0,
                        markerColor: AppConfig.success,
                        backgroundColor: !accuracyAchievement
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
                          "${L10n.of(context).time}: ${_formatTime(elapsedSeconds)}",
                      isAchievement: timeAchievement,
                      achievementText: "+ ${session.state.timeBonusXP} XP",
                      child: TimeStarsWidget(
                        elapsedSeconds: elapsedSeconds,
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
                          onPressed: () {
                            context.go('/rooms/analytics/vocab');
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                L10n.of(context).done,
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

  const TimeStarsWidget({
    required this.elapsedSeconds,
    super.key,
  });

  int get starCount {
    const timeForBonus = AnalyticsPracticeConstants.timeForBonus;
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
