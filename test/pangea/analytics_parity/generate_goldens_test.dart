import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'analytics_goldens.dart';

/// Writes goldens.json from the app's analytics formulas.
///
///     flutter test --dart-define=UPDATE_ANALYTICS_GOLDENS=true \
///       test/pangea/analytics_parity/generate_goldens_test.dart
///
/// Without the define (the normal suite run) it writes nothing and instead
/// proves the generator is deterministic: two independent builds must encode
/// to the same bytes, or a committed golden could never be checked.
/// goldens_check_test.dart compares a fresh build with the committed file.
const _update = bool.fromEnvironment('UPDATE_ANALYTICS_GOLDENS');

void main() {
  test('analytics goldens are generated deterministically', () async {
    final first = encodeGoldens(await buildAnalyticsGoldens());
    final second = encodeGoldens(await buildAnalyticsGoldens());
    expect(second, first, reason: 'two builds of the goldens differ');

    if (_update) {
      File(goldensPath).writeAsStringSync(first);
      // ignore: avoid_print
      print('Wrote $goldensPath');
    }
  });
}
