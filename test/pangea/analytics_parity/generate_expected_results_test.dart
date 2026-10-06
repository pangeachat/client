import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'analytics_parity_fixtures.dart';

/// Writes expected_results.json from the app's analytics formulas.
///
///     flutter test --dart-define=UPDATE_ANALYTICS_PARITY_FIXTURES=true \
///       test/pangea/analytics_parity/generate_expected_results_test.dart
///
/// Without the define (the normal suite run) it writes nothing and instead
/// proves the generator is deterministic: two independent builds must encode
/// to the same bytes, or committed expected results could never be checked.
/// expected_results_check_test.dart compares a fresh build with the committed file.
const _update = bool.fromEnvironment('UPDATE_ANALYTICS_PARITY_FIXTURES');

void main() {
  test(
    'analytics parity expected results are generated deterministically',
    () async {
      final first = encodeExpectedResults(await buildExpectedResults());
      final second = encodeExpectedResults(await buildExpectedResults());
      expect(
        second,
        first,
        reason: 'two builds of the expected results differ',
      );

      if (_update) {
        File(expectedResultsPath).writeAsStringSync(first);
        // ignore: avoid_print
        print('Wrote $expectedResultsPath');
      }
    },
  );
}
