import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';

/// The version tile's identity line. A build number cannot say what code is
/// running, and on a local build the commit SHA is empty by design — so a
/// locally-run app showed nothing but "<version>+<buildNumber>", identical
/// across every rebuild of the same checkout.
void main() {
  group('Environment.buildIdentifier', () {
    test('is empty when neither key is defined', () {
      // Both are compile-time constants and neither is defined in a test
      // process, which is exactly the "nothing honest to show" case.
      expect(Environment.buildCommitSha, isEmpty);
      expect(Environment.localBuildStamp, isEmpty);
      expect(Environment.buildIdentifier, isEmpty);
    });

    test('the local stamp does not make a local build look like CI', () {
      // The Sentry channel keys off the COMMIT SHA, not the identifier, so
      // stamping a dev build must not file it under ci.
      expect(
        Environment.sentryBuildTagsFor('')['build_channel'],
        'local',
        reason: 'an empty commit sha is a local build, stamped or not',
      );
      expect(Environment.sentryBuildTagsFor('abc12345')['build_channel'], 'ci');
    });
  });
}
