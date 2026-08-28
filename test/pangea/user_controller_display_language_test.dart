import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';

/// #8397 — [UserController.displayLanguageCode] is the shared resolver for the
/// language content displays in: the target language (L2) when the "app in
/// target language" toggle is on, else the native language (L1). Activity
/// hydration sends it as the choreo `l1` param, mirroring the app-copy locale
/// resolution in `MatrixState.setAppLanguage`.
class _FixedProfileUserController extends UserController {
  _FixedProfileUserController(this._profile);

  final Profile _profile;

  @override
  Profile get profile => _profile;
}

void main() {
  UserController controller({
    String? l1,
    String? l2,
    bool appLanguageIsTarget = false,
  }) => _FixedProfileUserController(
    Profile(
      userSettings: UserSettings(
        sourceLanguage: l1,
        targetLanguage: l2,
        appLanguageIsTarget: appLanguageIsTarget,
      ),
    ),
  );

  test('toggle off resolves to L1', () {
    expect(controller(l1: 'en', l2: 'es').displayLanguageCode, 'en');
  });

  test('toggle on resolves to L2', () {
    expect(
      controller(
        l1: 'en',
        l2: 'es',
        appLanguageIsTarget: true,
      ).displayLanguageCode,
      'es',
    );
  });

  test('toggle on with no L2 set falls back to L1', () {
    expect(
      controller(l1: 'en', appLanguageIsTarget: true).displayLanguageCode,
      'en',
    );
  });
}
