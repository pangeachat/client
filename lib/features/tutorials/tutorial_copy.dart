import 'package:flutter/widgets.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Runtime values tutorial copy needs that more than one host has to resolve.
/// The strings themselves stay in the step templates.
class TutorialCopy {
  /// A greeting in the learner's target language, borrowed from that locale's
  /// own UI copy rather than a new per-language content source. Falls back to
  /// the app language when there is no target language, or when the locale has
  /// no translation.
  ///
  /// Shared because the greeting fires on whichever surface the learner lands
  /// on first — the world map or a course plan.
  static Future<String> targetLanguageGreeting(BuildContext context) async {
    final fallback = L10n.of(context).welcome;
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) return fallback;
    try {
      return (await lookupL10n(Locale(l2.langCodeShort))).welcome;
    } catch (_) {
      return fallback;
    }
  }
}
