import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'analytics_goldens.dart';

/// Fails when the committed goldens.json no longer matches what the app's
/// analytics formulas produce. A change to a formula in lib/ then has to carry
/// the regenerated goldens in the same PR, which puts the changed figures in
/// the diff for review and hands them to admin-dash-api's parity tests.
void main() {
  test('committed analytics goldens match the app formulas', () async {
    final committedFile = File(goldensPath);
    expect(
      committedFile.existsSync(),
      isTrue,
      reason: '$goldensPath is missing. Generate it with: $regenerateCommand',
    );
    final committedText = committedFile.readAsStringSync();
    final fresh = await buildAnalyticsGoldens();
    final freshText = encodeGoldens(fresh);
    if (committedText == freshText) return;

    final diffs = diffGoldens(jsonDecode(committedText), fresh);
    final shown = diffs
        .take(40)
        .map((d) => d.length > 300 ? '${d.substring(0, 300)}...' : d)
        .join('\n');
    fail(
      'The committed $goldensPath is stale: the app analytics formulas now '
      'produce different figures.\n'
      '${diffs.isEmpty ? 'Formatting differs only.' : '${diffs.length} differing value(s):\n$shown'}\n\n'
      'If the formula change is intended, regenerate and commit the file in '
      'this PR:\n  $regenerateCommand',
    );
  });
}
