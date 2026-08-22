import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/routes/chat/calls/call_breadcrumb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a dropped crumb reads back, and clear erases it', () async {
    await CallBreadcrumb.drop(
      roomId: '!r:server',
      membershipEventId: r'$anchor',
    );
    final crumb = await CallBreadcrumb.read();
    expect(crumb, isNotNull);
    expect(crumb!.roomId, '!r:server');
    expect(crumb.membershipEventId, r'$anchor');

    await CallBreadcrumb.clear();
    expect(await CallBreadcrumb.read(), isNull);
  });

  test('an old crumb offers nothing and erases itself', () async {
    // Written directly at an age past the bound: the reload it could have
    // offered a return for is long over.
    SharedPreferences.setMockInitialValues({
      'pangea.call.breadcrumb':
          '{"roomId":"!r:server","membershipEventId":"\$anchor",'
          '"at":${DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch}}',
    });
    expect(await CallBreadcrumb.read(), isNull);
    final store = await SharedPreferences.getInstance();
    expect(
      store.getString('pangea.call.breadcrumb'),
      isNull,
      reason: 'expired means gone, not standing back up next start',
    );
  });

  test('a corrupt crumb is swallowed and erased', () async {
    SharedPreferences.setMockInitialValues({
      'pangea.call.breadcrumb': '{"roomId": 7}',
    });
    expect(await CallBreadcrumb.read(), isNull);
  });
}
