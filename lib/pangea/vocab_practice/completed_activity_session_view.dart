import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/level_up/star_rain_widget.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_bar/animated_progress_bar.dart';
import 'package:fluffychat/pangea/vocab_practice/percent_marker_bar.dart';
import 'package:fluffychat/pangea/vocab_practice/stat_card.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_page.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';

class CompletedActivitySessionView extends StatefulWidget {
  final VocabPracticeState controller;
  const CompletedActivitySessionView(this.controller, {super.key});

  @override
  State<CompletedActivitySessionView> createState() =>
      _CompletedActivitySessionViewState();
}

class _CompletedActivitySessionViewState
    extends State<CompletedActivitySessionView> {
  late final Map<String, double> progressChange;
  late double currentProgress;
  Uri? avatarUrl;
  bool shouldShowRain = false;

  @override
  void initState() {
    super.initState();

    // Fetch avatar URL
    final client = Matrix.of(context).client;
    client.fetchOwnProfile().then((profile) {
      if (mounted) {
        setState(() => avatarUrl = profile.avatarUrl);
      }
    });

    progressChange = widget.controller.calculateProgressChange(
      widget.controller.sessionLoader.value!.totalXpGained,
    );

    debugPrint(
      "Progress Change: ${progressChange['before']} -> ${progressChange['after']}",
    );

    //start with before progress
    currentProgress = progressChange['before'] ?? 0.0;

    //switch to after progress after first frame, to activate animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          currentProgress = progressChange['after'] ?? 0.0;
          // Start the star rain
          shouldShowRain = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final username =
        Matrix.of(context).client.userID?.split(':').first.substring(1) ?? '';

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16, right: 16, left: 16),
          child: Column(
            children: [
              Text(
                "Congratulations! You've completed the practice session.",
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
                      child: avatarUrl == null
                          ? Avatar(
                              name: username,
                              showPresence: false,
                              size: 100,
                            )
                          : ClipOval(
                              child: MxcImage(
                                uri: avatarUrl,
                                width: 100,
                                height: 100,
                              ),
                            ),
                    ),
                    Column(
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 16.0, bottom: 16.0),
                          child: AnimatedProgressBar(
                            height: 20.0,
                            widthPercent: currentProgress,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            duration: const Duration(milliseconds: 500),
                          ),
                        ),
                        Text(
                          "+ ${widget.controller.sessionLoader.value!.totalXpGained} XP",
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
                          "Accuracy: ${widget.controller.sessionLoader.value!.accuracy}%",
                      isAchievement:
                          (widget.controller.sessionLoader.value!.accuracy ==
                              100),
                      achievementText: "+ 5 XP",
                      child: PercentMarkerBar(
                        height: 20.0,
                        widthPercent:
                            widget.controller.sessionLoader.value!.accuracy /
                                100.0,
                        markerWidth: 20.0,
                        markerColor: AppConfig.success,
                        backgroundColor:
                            !(widget.controller.sessionLoader.value!.accuracy ==
                                    100)
                                ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                : Color.alphaBlend(
                                    AppConfig.goldLight.withOpacity(0.3),
                                    Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                      ),
                    ),
                    StatCard(
                      icon: Icons.my_location,
                      text: "Time: 0:35 sec", // TODO: Replace with actual time
                      isAchievement: false,
                      achievementText: "+ 5 XP",
                      child: PercentMarkerBar(
                        height: 20.0,
                        widthPercent: .5,
                        markerWidth: 20.0,
                        markerColor: Theme.of(context).colorScheme.primary,
                        backgroundColor: true
                            ? Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                            : Color.alphaBlend(
                                AppConfig.gold.withOpacity(0.1),
                                Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                      ),
                    ),
                    Column(
                      children: [
                        ElevatedButton(
                          onPressed: widget.controller.reloadSession,
                          child: const Text("Practice Again"),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text("Finish"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (shouldShowRain)
          const StarRainWidget(
            showBlast: true,
            rainDuration: Duration(seconds: 5),
          ),
      ],
    );
  }
}
