import 'package:flutter/material.dart';

import '../common/utils/error_handler.dart';

class ChoreoError {
  final Object? raw;

  ChoreoError({this.raw});

  String title(BuildContext context) => ErrorCopy(context, error: raw).title;

  String description(BuildContext context) =>
      ErrorCopy(context, error: raw).body;

  IconData get icon => Icons.error_outline;
}

class ChoreographerErrorController extends ChangeNotifier {
  ChoreoError? _error;
  int coolDownSeconds = 0;

  ChoreographerErrorController();

  bool get isError => _error != null;
  ChoreoError? get error => _error;
  Duration get defaultCooldown {
    coolDownSeconds += 3;
    return Duration(seconds: coolDownSeconds);
  }

  final List<String> _errorCache = [];

  void setError(ChoreoError? error) {
    if (_errorCache.contains(error?.raw.toString())) {
      return;
    }

    if (error != null) {
      _errorCache.add(error.raw.toString());
    }

    _error = error;
    Future.delayed(defaultCooldown, () {
      _error = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void setErrorAndLock(ChoreoError? error) {
    _error = error;
    notifyListeners();
  }

  void resetError() {
    _error = null;
    notifyListeners();
  }
}
