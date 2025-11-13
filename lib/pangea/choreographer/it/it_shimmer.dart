import 'dart:ui';

import 'package:flutter/material.dart';

class ItShimmer extends StatelessWidget {
  const ItShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.withAlpha(50);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: List.generate(3, (_) {
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(50, 36),
              backgroundColor: color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 7),
            ),
            onPressed: null,
            child: const Text(
              "          ", // 10 spaces
              style: TextStyle(
                color: Colors.transparent,
                fontSize: 16,
              ),
            ),
          ),
        );
      }),
    );
  }
}
