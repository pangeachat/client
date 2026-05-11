import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class ChoreoError {
  final Object raw;
  ChoreoError(this.raw);

  String toLocalizedString(BuildContext context) =>
      ErrorCopy(raw).toLocalizedString(context);
}

class ChoreographerErrorController extends ChangeNotifier {
  ChoreoError? _error;
  bool _blockWritingAssistance = false;

  ChoreographerErrorController();

  ChoreoError? get error => _error;
  bool get blockWritingAssistance => _error != null && _blockWritingAssistance;

  void setError(ChoreoError? error) {
    _error = error;
    _blockWritingAssistance = true;
    notifyListeners();
  }

  void unblockWritingAssistance() => _blockWritingAssistance = false;

  void clear() => setError(null);
}
