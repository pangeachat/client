import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';

/// #9440 — an open screen hears a setting change made in settings.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  test('setItem notifies after the new value is readable', () async {
    bool? heard;
    void listener() => heard = AppSettings.activityImageAsChatBackground.value;
    AppSettings.changes.addListener(listener);
    addTearDown(() => AppSettings.changes.removeListener(listener));

    await AppSettings.activityImageAsChatBackground.setItem(true);

    expect(heard, isTrue);
  });

  test('every setting type notifies', () async {
    var count = 0;
    void listener() => count++;
    AppSettings.changes.addListener(listener);
    addTearDown(() => AppSettings.changes.removeListener(listener));

    await AppSettings.sendOnEnter.setItem(true);
    await AppSettings.shareKeysWith.setItem('all');
    await AppSettings.textMessageMaxLength.setItem(100);
    await AppSettings.volume.setItem(0.5);

    expect(count, 4);
  });
}
