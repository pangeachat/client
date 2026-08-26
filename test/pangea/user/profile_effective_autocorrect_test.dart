import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/keyboards/keyboard_prompt_local_store.dart';
import 'package:fluffychat/features/user/user_model.dart';

/// #8504 — Profile.effectiveAutocorrect layers the observed-keyboard signal
/// on top of UserToolSettings.enableAutocorrectPlatformDefault, which stays
/// untouched (see user_tool_settings_migration_test.dart for its own,
/// platform-only coverage).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Profile makeProfile({bool? autocorrectChoice, String? targetLanguage}) =>
      Profile(
        userSettings: UserSettings(targetLanguage: targetLanguage),
        toolSettings: UserToolSettings(enableAutocorrect: autocorrectChoice),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ObservedKeyboardStore.initialize();
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('an explicit choice always wins, regardless of observation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final profile = makeProfile(autocorrectChoice: false, targetLanguage: 'es');
    await ObservedKeyboardStore.markObserved('es');
    expect(profile.effectiveAutocorrect, isFalse);
  });

  test('Android stays on regardless of observation', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final profile = makeProfile(targetLanguage: 'es');
    expect(profile.effectiveAutocorrect, isTrue);
  });

  test('iOS stays off until this device has observed a matching keyboard', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final profile = makeProfile(targetLanguage: 'es');
    expect(profile.effectiveAutocorrect, isFalse);
  });

  test(
    'iOS turns on once this device has observed a matching keyboard',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final profile = makeProfile(targetLanguage: 'es');
      await ObservedKeyboardStore.markObserved('es-MX');
      expect(profile.effectiveAutocorrect, isTrue);
    },
  );

  test(
    'observing one language does not turn autocorrect on for another',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final profile = makeProfile(targetLanguage: 'ja');
      await ObservedKeyboardStore.markObserved('es');
      expect(profile.effectiveAutocorrect, isFalse);
    },
  );
}
