/// Error result returned by localization endpoints for individual IDs
/// that could not be localized (e.g., not found, internal server error).
class LocalizationErrorResult {
  final String errorCode;
  final String error;

  const LocalizationErrorResult({
    required this.errorCode,
    required this.error,
  });

  factory LocalizationErrorResult.fromJson(Map<String, dynamic> json) {
    return LocalizationErrorResult(
      errorCode: json['errorCode'] as String,
      error: json['error'] as String,
    );
  }

  /// Returns true if the JSON map represents a localization error
  /// (has an 'errorCode' field) rather than a success result.
  static bool isError(Map<String, dynamic> json) {
    return json.containsKey('errorCode');
  }

  bool get isNotFound => errorCode == 'not-found';
  bool get isInternalServerError => errorCode == 'internal-server-error';
}
