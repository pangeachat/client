import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Host side of the performance benchmark: saves each run's results, stamped
/// with the commit and time, to `build/perf/` for later comparison.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    // Every benchmark reports a result. A run that passed without one did not
    // measure anything, so it must not look like a pass.
    if (data == null || data['passes'] is! List) {
      stderr.writeln(
        'The run passed but reported no benchmark result, so nothing was '
        'measured.',
      );
      exit(1);
    }
    // A run with uncommitted changes did not measure the commit it names.
    final dirty = Process.runSync('git', [
      'status',
      '--porcelain',
    ]).stdout.toString().trim().isNotEmpty;
    final commit =
        Process.runSync('git', [
          'rev-parse',
          '--short',
          'HEAD',
        ]).stdout.toString().trim() +
        (dirty ? '-dirty' : '');
    final now = DateTime.now().toUtc();
    data['commit'] = commit;
    data['recordedAt'] = now.toIso8601String();
    final stamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    await writeResponseData(
      data,
      testOutputFilename: '${data['scenario']}_${data['platform']}_$stamp',
      destinationDirectory: 'build/perf',
    );
  },
);
