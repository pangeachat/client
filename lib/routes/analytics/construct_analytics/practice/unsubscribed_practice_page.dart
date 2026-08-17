import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/widgets/decorative_stars.dart';
import 'package:fluffychat/features/subscription/widgets/locked_shimmer_box.dart';
import 'package:fluffychat/features/subscription/widgets/unlock_button.dart';
import 'package:fluffychat/l10n/l10n.dart';

class UnsubscribedPracticePage extends StatelessWidget {
  const UnsubscribedPracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final exampleMessageColor = primaryColor.withAlpha(50);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 16.0),
                      // Title
                      const LockedShimmerBox(width: 250, height: 30),
                      const SizedBox(height: 8.0),
                      // Phonetic transcription
                      const LockedShimmerBox(width: 150, height: 20),
                      const SizedBox(height: 24.0),
                      // Center content box (example message)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: LockedShimmerBox(
                          baseColor: exampleMessageColor,
                          width: double.infinity,
                          height: 80.0,
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      const SizedBox(height: 24.0),
                      // Choice cards
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          spacing: 8.0,
                          children: [
                            for (int i = 0; i < 4; i++)
                              LockedShimmerBox(
                                width: double.infinity,
                                height: 60.0,
                                borderRadius: BorderRadius.circular(12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              DecorativeStars(
                stars: [
                  DecorativeStarSpec(
                    size: isColumnMode ? 80 : 35,
                    top: 20,
                    left: 20,
                    rotation: -math.pi / 8,
                  ),
                  DecorativeStarSpec(
                    size: isColumnMode ? 90 : 40,
                    top: 30,
                    right: 30,
                    rotation: math.pi / 6,
                  ),
                  DecorativeStarSpec(
                    size: isColumnMode ? 70 : 35,
                    top: 440,
                    left: -5,
                    rotation: math.pi / 4,
                  ),
                  DecorativeStarSpec(
                    size: isColumnMode ? 75 : 35,
                    top: 450,
                    right: -5,
                    rotation: -math.pi / 5,
                  ),
                ],
              ),
              Center(child: Icon(Icons.lock, size: 80, color: primaryColor)),
            ],
          ),
        ),
        Container(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: UnlockButton(
              label: L10n.of(context).unlockPracticeActivities,
              fontSize: 18.0,
              padding: const EdgeInsets.all(16.0),
            ),
          ),
        ),
      ],
    );
  }
}
