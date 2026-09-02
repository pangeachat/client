import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  // The diff underline is a graphical object carrying the changed/unchanged
  // signal, so 3:1 under 1.4.11 — not the 4.5:1 that text would need.
  const minRatio = 3.0;

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('status foreground colours clear $minRatio:1 in '
        '${brightness.name}', (tester) async {
      final scheme = ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: const Color(0xFF8560E0),
      );
      late Color success;
      late Color warning;
      late Color error;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            brightness: brightness,
            colorScheme: scheme,
          ),
          home: Builder(
            builder: (context) {
              success = AppConfig.successByTheme(context);
              warning = AppConfig.warningByTheme(context);
              error = Theme.of(context).colorScheme.error;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final background in [
        scheme.surface,
        scheme.surfaceContainerHighest,
      ]) {
        for (final entry in {
          'success': success,
          'warning': warning,
          'error': error,
        }.entries) {
          expect(
            contrast(entry.value, background),
            greaterThanOrEqualTo(minRatio),
            reason:
                '${entry.key} ${entry.value} on $background '
                'in ${brightness.name}',
          );
        }
      }
    });
  }
}
