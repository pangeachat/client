// ignore_for_file: constant_identifier_names

import 'package:matrix/matrix_api_lite.dart';

enum DeleteAccountError {
  P_UNKNOWN,
  P_LIMIT_EXCEEDED,
  P_BAD_JSON,
  P_INVALID_ACTION,
  P_INVALID_USER_ID,
  P_INVALID_STATE,
  P_FORBIDDEN,
  P_SERVER_ERROR;

  static DeleteAccountError fromErrorMessage(String errorMessage) {
    switch (errorMessage) {
      case 'Too many requests':
        return DeleteAccountError.P_LIMIT_EXCEEDED;
      case 'Invalid JSON in request body':
        return DeleteAccountError.P_BAD_JSON;
      case 'Invalid action. Must be one of: schedule, cancel, force':
        return DeleteAccountError.P_INVALID_ACTION;
      case 'Missing or invalid user_id':
      case 'Can only delete local users':
        return DeleteAccountError.P_INVALID_USER_ID;
      case 'No delete schedule found for user':
        return DeleteAccountError.P_INVALID_STATE;
      case 'Forbidden: server admin required':
      case 'Forbidden':
        return DeleteAccountError.P_FORBIDDEN;
      case 'Internal server error':
        return DeleteAccountError.P_SERVER_ERROR;
      default:
        return DeleteAccountError.P_UNKNOWN;
    }
  }
}

/// Represents a special response from the Homeserver for errors.
class DeleteAccountException implements Exception {
  final Map<String, Object?> raw;

  DeleteAccountException(this.raw);

  String get errorMessage => raw.tryGet<String>('error') ?? 'Unknown error';

  DeleteAccountError get error =>
      DeleteAccountError.fromErrorMessage(errorMessage);
}
