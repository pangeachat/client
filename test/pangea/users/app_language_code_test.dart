import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';

/// Keeps the profile in memory so the resolver can be driven without a Matrix
/// client or account data.
class _StubUserController extends UserController {
  _StubUserController(this._profile);

  final Profile _profile;

  @override
  Profile get profile => _profile;
}

UserController _controllerWith({
  String? sourceLanguage,
  String? targetLanguage,
  bool appLanguageIsTarget = false,
}) => _StubUserController(
  Profile(
    userSettings: UserSettings(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      appLanguageIsTarget: appLanguageIsTarget,
    ),
  ),
);

/// #8397 — the one resolved "display language" the app presents itself in:
/// UI copy and localized content (activity plans) both follow it. The "App in
/// target language" toggle points it at L2; off, it is the L1 — the same value
/// every pre-toggle caller read.
void main() {
  group('UserController.appLanguageCode', () {
    test('toggle off resolves to the L1', () {
      final controller = _controllerWith(
        sourceLanguage: 'en',
        targetLanguage: 'es',
      );
      expect(controller.appLanguageCode, 'en');
      expect(controller.appLanguageCode, controller.userL1Code);
    });

    test('toggle on resolves to the L2', () {
      final controller = _controllerWith(
        sourceLanguage: 'en',
        targetLanguage: 'es',
        appLanguageIsTarget: true,
      );
      expect(controller.appLanguageCode, 'es');
    });

    test('toggle on with no L2 set falls back to the L1', () {
      final controller = _controllerWith(
        sourceLanguage: 'en',
        appLanguageIsTarget: true,
      );
      expect(controller.appLanguageCode, 'en');
    });

    test('toggle on with an empty L2 falls back to the L1', () {
      final controller = _controllerWith(
        sourceLanguage: 'en',
        targetLanguage: '',
        appLanguageIsTarget: true,
      );
      expect(controller.appLanguageCode, 'en');
    });

    test('regional codes pass through untouched', () {
      final controller = _controllerWith(
        sourceLanguage: 'en',
        targetLanguage: 'es-MX',
        appLanguageIsTarget: true,
      );
      expect(controller.appLanguageCode, 'es-MX');
    });
  });
}
