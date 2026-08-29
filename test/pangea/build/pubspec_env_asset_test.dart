import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The `.env` asset line must stay COMMENTED in the repository.
///
/// `.env` is gitignored, and Flutter fails a build that declares an asset which
/// is not there -- so an uncommented line breaks CI for everyone, on a file
/// nobody was editing. CI uncomments it itself for mobile builds
/// (`scripts/enable_mobile_env.patch`), and the local-dev tooling uncomments it
/// in the working tree so an Android build can bundle real config.
///
/// That is exactly why it keeps being committed by accident: the line is
/// legitimately uncommented on any machine that has run the local setup, so a
/// `git add -A` sweeps it up with unrelated work. It has now happened twice,
/// and the second time it rode along with a commit about something else
/// entirely. A comment asking people not to do it did not stop it; this will,
/// at the cost of one assertion.
void main() {
  test('the .env asset line stays commented', () {
    // Read from the COMMITTED tree, not the working one. The local setup
    // uncomments the line on purpose so an Android build can bundle real
    // config, and failing a developer's test run for doing what the tooling
    // told it to would make this a nuisance rather than a guard. What must
    // never happen is that state being COMMITTED, which is what this reads.
    final show = Process.runSync('git', ['show', 'HEAD:pubspec.yaml']);
    if (show.exitCode != 0) {
      markTestSkipped('not a git checkout; nothing committed to check');
      return;
    }
    final lines = (show.stdout as String).split('\n');
    final declared = lines
        .where((l) => RegExp(r'^\s*-\s*\.env\s*$').hasMatch(l))
        .toList();

    expect(
      declared,
      isEmpty,
      reason:
          'pubspec.yaml declares the .env asset. It is gitignored, so this '
          'fails the build wherever the file does not exist -- CI included. '
          'Re-comment it (`# - .env`); CI and the local tooling each uncomment '
          'it themselves when they need it.',
    );

    // And the commented form must still be THERE: if someone deletes the line
    // instead of commenting it, CI's patch has nothing to uncomment and mobile
    // builds lose their config with no failure to say so.
    expect(
      lines.any((l) => RegExp(r'^\s*#\s*-\s*\.env\s*$').hasMatch(l)),
      isTrue,
      reason:
          'the commented `# - .env` line is gone; scripts/enable_mobile_env.patch '
          'needs it to exist in order to uncomment it for mobile builds',
    );
  });
}
