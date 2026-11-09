import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';

/// #9683 — a language change erased the cached activity plans, and a saved
/// session's goals count only once its plan is loaded, so the Mission card's
/// Conversation XP dropped after a switch and refilled batch by batch.
void main() {
  LanguageModel lang(String code) =>
      LanguageModel(langCode: code, displayName: code);

  test('a target-language switch keeps the activity plans', () {
    final kept = PangeaController.cachesKeptOnLanguageUpdate(
      LanguageUpdate(
        prevBaseLang: lang('en'),
        baseLang: lang('en'),
        prevTargetLang: lang('es'),
        targetLang: lang('fr'),
      ),
    );

    expect(kept, contains('activity_plan_storage'));
  });

  test('a base-language switch keeps the activity plans', () {
    final kept = PangeaController.cachesKeptOnLanguageUpdate(
      LanguageUpdate(
        prevBaseLang: lang('en'),
        baseLang: lang('de'),
        prevTargetLang: lang('es'),
        targetLang: lang('es'),
      ),
    );

    expect(kept, contains('activity_plan_storage'));
    // Course data still follows the base language.
    expect(kept, isNot(contains('course_storage')));
  });
}
