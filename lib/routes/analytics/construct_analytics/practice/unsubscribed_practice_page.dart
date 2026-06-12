import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_box.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _DecorativeStar extends StatelessWidget {
  final double size;
  final double rotation;

  const _DecorativeStar({required this.size, this.rotation = 0});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Opacity(
        opacity: .25,
        child: Text('⭐', style: TextStyle(fontSize: size)),
      ),
    );
  }
}

class UnsubscribedPracticePage extends StatelessWidget {
  const UnsubscribedPracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final placeholderColor = isDarkMode
        ? Colors.white.withAlpha(50)
        : Colors.black.withAlpha(50);
    final primaryColor = theme.colorScheme.primary;
    final exampleMessageColor = Color.alphaBlend(
      ThemeData.dark().colorScheme.primary,
      Colors.white,
    ).withAlpha(50);
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
                      ShimmerBox(
                        baseColor: placeholderColor,
                        highlightColor: primaryColor,
                        width: 250,
                        height: 30,
                      ),
                      const SizedBox(height: 8.0),
                      // Phonetic transcription
                      ShimmerBox(
                        baseColor: placeholderColor,
                        highlightColor: primaryColor,
                        width: 150,
                        height: 20,
                      ),
                      const SizedBox(height: 24.0),
                      // Center content box (example message)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: ShimmerBox(
                          baseColor: exampleMessageColor,
                          highlightColor: primaryColor,
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
                          children: List.generate(
                            4,
                            (index) => ShimmerBox(
                              baseColor: placeholderColor,
                              highlightColor: primaryColor,
                              width: double.infinity,
                              height: 60.0,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 20,
                left: 20,
                child: _DecorativeStar(
                  size: isColumnMode ? 80 : 35,
                  rotation: -math.pi / 8,
                ),
              ),
              Positioned(
                top: 30,
                right: 30,
                child: _DecorativeStar(
                  size: isColumnMode ? 90 : 40,
                  rotation: math.pi / 6,
                ),
              ),
              Positioned(
                top: 440,
                left: -5,
                child: _DecorativeStar(
                  size: isColumnMode ? 70 : 35,
                  rotation: math.pi / 4,
                ),
              ),
              Positioned(
                top: 450,
                right: -5,
                child: _DecorativeStar(
                  size: isColumnMode ? 75 : 35,
                  rotation: -math.pi / 5,
                ),
              ),
              Center(child: Icon(Icons.lock, size: 80, color: primaryColor)),
            ],
          ),
        ),
        Container(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: PressableButton(
              borderRadius: BorderRadius.circular(36),
              color: primaryColor,
              onPressed: () {
                MatrixState.pangeaController.subscriptionController.showPaywall(
                  context,
                );
              },
              builder: (context, depressed, shadowColor) => Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: depressed ? shadowColor : primaryColor,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: Text(
                  L10n.of(context).unlockPracticeActivities,
                  style: TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
