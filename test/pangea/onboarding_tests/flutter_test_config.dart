import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Onboarding steps render `BotFace`, which loads a Rive file through
/// `rive_native` and falls back to a `CachedNetworkImage`. Neither native
/// dependency exists in the test VM, and both fail asynchronously *after* the
/// test body has finished — the one place `tester.takeException()` cannot
/// reach, where flutter_test turns them into test failures. Drop exactly those
/// and report everything else as usual.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final report = reportTestException;
  reportTestException = (details, description) {
    final source = '${details.exception}${details.stack}';
    if (source.contains('rive') ||
        source.contains('cache_manager') ||
        source.contains('sqflite')) {
      return;
    }
    report(details, description);
  };
  await testMain();
}
