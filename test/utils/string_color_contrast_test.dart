import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/string_color.dart';

/// #8762 — exhaustive WCAG 2.1 SC 1.4.3 audit of the name-derived palette.
/// The palette is a closed set (12 buckets per getter), so every case is
/// enumerated exactly instead of sampled from rendered pixels — axe and
/// Lighthouse cannot see into the canvas renderer. Backgrounds mirror
/// production: the M3 scheme from the default seed, and the avatar's
/// white/black backing Material. The full contrast report prints on each run.
void main() {
  // One name per bucket: each name's code-unit sum % 12 equals its index.
  const bucketNames = [
    'H', 'I', 'J', 'K', 'L', 'A', // buckets 0–5
    'B', 'C', 'D', 'E', 'F', 'G', // buckets 6–11
  ];

  final lightScheme = ColorScheme.fromSeed(seedColor: AppConfig.primaryColor);
  final darkScheme = ColorScheme.fromSeed(
    seedColor: AppConfig.primaryColor,
    brightness: Brightness.dark,
  );

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  String hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  String row(int bucket, Color fg, Color bg) =>
      '  bucket $bucket  ${hex(Color.alphaBlend(fg, bg))} on ${hex(bg)}'
      '  ${contrast(Color.alphaBlend(fg, bg), bg).toStringAsFixed(2)}:1';

  test('every name lands in its expected colour bucket', () {
    expect([
      for (final name in bucketNames) name.colorBucket,
    ], List.generate(12, (i) => i));
  });

  test(
    'avatar initials: white ink clears 4.5:1 on every fill, both themes',
    () {
      final report = StringBuffer('WCAG report — avatar fills vs white ink\n');
      for (var bucket = 0; bucket < 12; bucket++) {
        final name = bucketNames[bucket];
        // The fill renders at alpha 0.75 over the avatar's backing Material:
        // white in light theme, black in dark (avatar.dart).
        final fillLight = Color.alphaBlend(name.avatarColorLight, Colors.white);
        final fillDark = Color.alphaBlend(name.avatarColorDark, Colors.black);
        report
          ..writeln(
            '  light${row(bucket, name.avatarColorLight, Colors.white)}',
          )
          ..writeln(
            '  dark ${row(bucket, name.avatarColorDark, Colors.black)}',
          );
        expect(
          contrast(Colors.white, fillLight),
          greaterThanOrEqualTo(4.5),
          reason: 'bucket $bucket light fill ${hex(fillLight)}',
        );
        expect(
          contrast(Colors.white, fillDark),
          greaterThanOrEqualTo(4.5),
          reason: 'bucket $bucket dark fill ${hex(fillDark)}',
        );
      }
      debugPrint(report.toString());
    },
  );

  test('name colours clear 4.5:1 on surface and darkest card, both themes', () {
    final report = StringBuffer('WCAG report — name colours vs backgrounds\n');
    final cases = <String, (Color Function(String), List<Color>)>{
      'timeline light': (
        (name) => name.timelineNameColor(Brightness.light),
        [lightScheme.surface, lightScheme.surfaceContainerHighest],
      ),
      'timeline dark': (
        (name) => name.timelineNameColor(Brightness.dark),
        [darkScheme.surface, darkScheme.surfaceContainerHighest],
      ),
      'profile light': (
        (name) => name.profileNameColor(Brightness.light),
        [lightScheme.surface, lightScheme.surfaceContainerHighest],
      ),
      'profile dark': (
        (name) => name.profileNameColor(Brightness.dark),
        [darkScheme.surface, darkScheme.surfaceContainerHighest],
      ),
    };
    cases.forEach((label, testCase) {
      final (colorOf, backgrounds) = testCase;
      report.writeln(label);
      for (var bucket = 0; bucket < 12; bucket++) {
        final name = bucketNames[bucket];
        for (final background in backgrounds) {
          final rendered = Color.alphaBlend(colorOf(name), background);
          report.writeln(row(bucket, colorOf(name), background));
          expect(
            contrast(rendered, background),
            greaterThanOrEqualTo(4.5),
            reason:
                '$label bucket $bucket ${hex(rendered)} on '
                '${hex(background)}',
          );
        }
      }
    });
    debugPrint(report.toString());
  });
}
