import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/routes/settings/settings_learning/first_switch_confirmation_repo.dart';

/// #8495 — whether the learner has already seen the "starts at level 1"
/// confirmation for a given language, permanently, per language
/// (profile.instructions.md, "Switching from context": "says so once").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'first_switch_confirmation',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('first_switch_confirmation');
  });

  test('an unseen language has not been confirmed', () {
    expect(FirstSwitchConfirmationRepo.hasConfirmed('es'), isFalse);
  });

  test(
    'confirming a language is remembered, and only for that language',
    () async {
      await FirstSwitchConfirmationRepo.setConfirmed('it');

      expect(FirstSwitchConfirmationRepo.hasConfirmed('it'), isTrue);
      expect(FirstSwitchConfirmationRepo.hasConfirmed('de'), isFalse);
    },
  );
}
