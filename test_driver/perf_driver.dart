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
    final stale = _staleBuild(data['platform'] as String?);
    if (stale != null) {
      stderr.writeln(stale);
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

/// Why the app this run measured is older than the code it should contain, or
/// null. When its build fails (a compile error, a locked iPhone), `flutter
/// drive` still launches the app already on the device, and the run measures
/// that older code without any error.
String? _staleBuild(String? platform) {
  // A prebuilt app (--use-application-binary, as comparisons use) is the
  // tester's explicit choice and is older than the code by design.
  final parent = Process.runSync('ps', [
    '-o',
    'ppid=',
    '-p',
    '$pid',
  ]).stdout.toString().trim();
  final drive = Process.runSync('ps', [
    '-o',
    'command=',
    '-p',
    parent,
  ]).stdout.toString();
  if (drive.isEmpty) return 'Could not read the flutter drive command.';
  if (drive.contains('--use-application-binary')) return null;

  final binary = switch (platform) {
    'android' => File('build/app/outputs/flutter-apk/app-profile.apk'),
    'iOS' => File('build/ios/iphoneos/Runner.app/Frameworks/App.framework/App'),
    _ => null,
  };
  if (binary == null) return 'No build check for platform $platform.';
  if (!binary.existsSync()) return 'No app build at ${binary.path}.';
  final built = binary.lastModifiedSync();

  final sources = [
    File('pubspec.yaml'),
    File('pubspec.lock'),
    for (final dir in ['lib', 'integration_test'])
      ...Directory(dir).listSync(recursive: true).whereType<File>(),
  ];
  final newest = sources.reduce(
    (a, b) => a.lastModifiedSync().isAfter(b.lastModifiedSync()) ? a : b,
  );
  if (!newest.lastModifiedSync().isAfter(built)) return null;
  return 'The app on the device was built at $built, before ${newest.path} '
      'last changed, so this run measured older code. The build probably '
      'failed; check the output above and run again.';
}
