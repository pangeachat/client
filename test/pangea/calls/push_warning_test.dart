import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/utils/background_push.dart';

void main() {
  test('a build without Firebase never warns about push', () {
    // The GOOGLE_SERVICES-stripped build cannot get a token by construction;
    // the popup it used to raise reported a working build as broken.
    expect(BackgroundPush.shouldWarnNoPush(firebaseEnabled: false), isFalse);
  });

  test('a push-enabled build still warns on a real failure', () {
    expect(BackgroundPush.shouldWarnNoPush(firebaseEnabled: true), isTrue);
  });
}
