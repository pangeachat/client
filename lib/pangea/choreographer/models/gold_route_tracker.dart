import 'package:fluffychat/pangea/choreographer/models/completed_it_step.dart';

class GoldRouteTracker {
  final String _originalText;
  final List<Continuance> continuances;

  const GoldRouteTracker(this.continuances, String originalText)
      : _originalText = originalText;

  Continuance? currentContinuance({
    required String currentText,
    required String sourceText,
  }) {
    if (_originalText != sourceText) {
      return null;
    }

    String stack = "";
    for (final cont in continuances) {
      if (stack == currentText) {
        return cont;
      }
      stack += cont.text;
    }

    return null;
  }

  String? get fullTranslation {
    if (continuances.isEmpty) return null;
    String full = "";
    for (final cont in continuances) {
      full += cont.text;
    }
    return full;
  }
}
