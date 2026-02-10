import 'package:fluffychat/pangea/choreographer/it/completed_it_step_model.dart';

class GoldRouteTrackerModel {
  final String _originalText;
  final List<ContinuanceModel> continuances;

  const GoldRouteTrackerModel(this.continuances, String originalText)
    : _originalText = originalText;

  ContinuanceModel? currentContinuance({
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
