import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/routes/chat/calls/call_breadcrumb.dart';

void main() {
  // A rejoin has no other way to know what kind of call it is returning to.
  // Coming back always as audio left a video call with the camera off and the
  // other person's picture gone for good.
  test('remembers whether the call had video', () async {
    SharedPreferences.setMockInitialValues({});
    await CallBreadcrumb.drop(
      account: 'one',
      roomId: '!r:server',
      membershipEventId: r'$mem',
      video: true,
    );
    expect((await CallBreadcrumb.read('one'))!.video, isTrue);

    await CallBreadcrumb.drop(
      account: 'one',
      roomId: '!r:server',
      membershipEventId: r'$mem',
    );
    expect(
      (await CallBreadcrumb.read('one'))!.video,
      isFalse,
      reason: 'a voice call must not come back with the camera on',
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a dropped crumb reads back, and clear erases it', () async {
    await CallBreadcrumb.drop(
      account: 'one',
      roomId: '!r:server',
      membershipEventId: r'$anchor',
    );
    final crumb = await CallBreadcrumb.read('one');
    expect(crumb, isNotNull);
    expect(crumb!.roomId, '!r:server');
    expect(crumb.membershipEventId, r'$anchor');

    await CallBreadcrumb.clear('one');
    expect(await CallBreadcrumb.read('one'), isNull);
  });

  test('an old crumb offers nothing and erases itself', () async {
    // Written directly at an age past the bound: the reload it could have
    // offered a return for is long over.
    SharedPreferences.setMockInitialValues({
      'pangea.call.breadcrumb.one':
          '{"roomId":"!r:server","membershipEventId":"\$anchor",'
          '"at":${DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch}}',
    });
    expect(await CallBreadcrumb.read('one'), isNull);
    final store = await SharedPreferences.getInstance();
    expect(
      store.getString('pangea.call.breadcrumb.one'),
      isNull,
      reason: 'expired means gone, not standing back up next start',
    );
  });

  // Two accounts on one phone are two calls to come back to. A single global
  // key made them one: the second account's clean teardown erased the first
  // account's way back to a call somebody was still sitting in.
  test('one account cannot erase another account\'s way back', () async {
    await CallBreadcrumb.drop(
      account: 'one',
      roomId: '!theirs:server',
      membershipEventId: r'$mine',
    );
    await CallBreadcrumb.drop(
      account: 'two',
      roomId: '!other:server',
      membershipEventId: r'$other',
    );

    await CallBreadcrumb.clear('two');

    expect(
      (await CallBreadcrumb.read('one'))?.roomId,
      '!theirs:server',
      reason: 'the other account was still in that call',
    );
    expect(await CallBreadcrumb.read('two'), isNull);
  });

  test('a corrupt crumb is swallowed and erased', () async {
    SharedPreferences.setMockInitialValues({
      'pangea.call.breadcrumb.one': '{"roomId": 7}',
    });
    expect(await CallBreadcrumb.read('one'), isNull);
  });
}
