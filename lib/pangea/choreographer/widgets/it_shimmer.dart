import 'dart:ui';

import 'package:flutter/material.dart';

class ItShimmer extends StatelessWidget {
  const ItShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> dummyStrings = [];
    for (int i = 0; i < 3; i++) {
      dummyStrings.add(" " * 10);
    }
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        ...dummyStrings.map(
          (e) => Container(
            constraints: const BoxConstraints(minWidth: 50),
            margin: const EdgeInsets.all(2),
            padding: EdgeInsets.zero,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: TextButton(
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 7),
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.all<Color>(
                    Theme.of(context).colorScheme.primary.withAlpha(50),
                  ),
                ),
                onPressed: null,
                child: Text(
                  e,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: Colors.transparent,
                        fontSize: 16,
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
