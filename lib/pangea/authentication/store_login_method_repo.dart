import 'package:collection/collection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

enum LoginMethod {
  google,
  apple,
  email;

  String label(L10n l10n) => switch (this) {
    LoginMethod.google => 'Google',
    LoginMethod.apple => 'Apple',
    LoginMethod.email => l10n.emailLoginMethod,
  };
}

class LoginMethodConstants {
  static const String lastLoginMethod = 'pangea.last_login_method';
  static const String lastLoginUserID = 'pangea.last_login_user_id';
}

class PreviousLoginInfo {
  final String userID;
  final LoginMethod method;

  const PreviousLoginInfo({required this.userID, required this.method});

  Map<String, dynamic> toJson() => {
    LoginMethodConstants.lastLoginMethod: method.name,
    LoginMethodConstants.lastLoginUserID: userID,
  };
}

class LoginMethodRepo {
  static Future<void> storeLoginMethod({
    required String userID,
    required LoginMethod method,
  }) async {
    try {
      final storage = FlutterSecureStorage();
      await storage.write(
        key: LoginMethodConstants.lastLoginUserID,
        value: userID,
      );
      await storage.write(
        key: LoginMethodConstants.lastLoginMethod,
        value: method.name,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'userID': userID, 'method': method.name},
      );
    }
  }

  static Future<PreviousLoginInfo?> getStoredLoginMethod() async {
    String? userID;
    LoginMethod? method;

    try {
      final storage = FlutterSecureStorage();
      userID = await storage.read(key: LoginMethodConstants.lastLoginUserID);
      final storedMethod = await storage.read(
        key: LoginMethodConstants.lastLoginMethod,
      );
      method = LoginMethod.values.firstWhereOrNull(
        (m) => m.name == storedMethod,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'userID': userID, 'method': method},
      );
    }

    if (method == null || userID == null) return null;
    return PreviousLoginInfo(userID: userID, method: method);
  }
}
