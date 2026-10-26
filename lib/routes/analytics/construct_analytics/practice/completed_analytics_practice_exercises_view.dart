import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/offline_practice_note.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/percent_marker_bar.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_xp.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/stat_card.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/text_loading_shimmer.dart';

class CompletedAnalyticsPracticeExercisesView extends StatelessWidget {
  final AnalyticsPracticeSessionModel session;

  /// Null until the session's last uses are recorded and measuring starts.
  final Future<PracticeSessionXp>? earnedXp;
  final VoidCallback launchSession;
  final Future<double> levelProgress;

  const CompletedAnalyticsPracticeExercisesView({
    required this.session,
    required this.earnedXp,
    required this.launchSession,
    required this.levelProgress,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 16, left: 16),
      child: SingleChildScrollView(
        child: Column(
          spacing: 32.0,
          children: [
            Text(
              session.getCompletionMessage(context),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            FutureBuilder(
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
            _EarnedXp(earnedXp),
            StatCard(
              icon: Icons.my_location,
              text: "${L10n.of(context).accuracy}: $accuracy%",
              isAchievement: accuracyAchievement,
              achievementText: "+ ${session.state.accuracyBonusXP} XP",
              child: PercentMarkerBar(
                height: 20.0,
                widthPercent: accuracy / 100.0,
                markerWidth: 20.0,
                markerColor: Theme.of(context).pangea.successGraphic,
                // The neutral track, washed gold when the accuracy bonus
                // was earned.
                backgroundColor: !accuracyAchievement
                    ? null
                    : Color.alphaBlend(
                        Theme.of(
                          context,
                        ).pangea.goldFixedDim.withValues(alpha: 0.3),
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatCard(
                  icon: Icons.alarm,
                  text:
                      "${L10n.of(context).time}: ${_formatTime(elapsedSeconds)}",
                  isAchievement: timeAchievement,
                  achievementText: "+ ${session.state.timeBonusXP} XP",
                ),
                const OfflinePracticeNote.completed(
                  padding: EdgeInsets.only(top: 32.0),
                ),
              ],
            ),
            Column(
              spacing: 16.0,
              children: [
                //expanded row button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                  ),
                  onPressed: launchSession,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text(L10n.of(context).anotherRound)],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                  ),
                  onPressed: () {
                    // #7227: return to the analytics page the practice was
                    // launched from (vocab or grammar) via the world_v2 token,
                    // not the dead legacy `/rooms/analytics/...` path. Practice
                    // is a right-column takeover, so swap it back for the
                    // matching analytics summary tab.
                    context.go(
                      WorkspaceNav.openAnalytics(
                        GoRouterState.of(context).uri,
                        subpage: session.type.indicator,
                      ),
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text(L10n.of(context).done)],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The XP the session counted and, in Objective practice, what its Mission
/// gained (#9633).
class _EarnedXp extends StatelessWidget {
  final Future<PracticeSessionXp>? earnedXp;

  const _EarnedXp(this.earnedXp);

  static String _signed(int xp) => xp < 0 ? '− ${-xp}' : '+ $xp';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = theme.textTheme.titleLarge?.copyWith(
      color: theme.pangea.gold,
      fontWeight: FontWeight.bold,
    );
    return FutureBuilder<PracticeSessionXp>(
      future: earnedXp,
      builder: (context, snapshot) {
        // The failure is reported where it is measured; a number that may be
        // wrong is worse than none.
        if (snapshot.hasError) return const SizedBox.shrink();
        final xp = snapshot.data;
        if (xp == null) {
          return TextLoadingShimmer(
            width: 96.0,
            height: MediaQuery.textScalerOf(
              context,
            ).scale(headline?.fontSize ?? 22.0),
          );
        }
        final missionGain = xp.missionGain;
        return Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 4.0,
          children: [
            Text('${_signed(xp.counted)} XP', style: headline),
            if (missionGain != null)
              Text(
                L10n.of(context).xpTowardMission(_signed(missionGain)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        );
      },
    );
  }
}
