import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/chat_settings/pages/space_analytics.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';

class _AnalyticsRequestEntry {
  final RequestStatus status;
  final DateTime timestamp;

  _AnalyticsRequestEntry({
    required this.status,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  _AnalyticsRequestEntry.fromJson(Map<String, dynamic> json)
      : status = RequestStatus.fromString(json['status']) ??
            RequestStatus.unrequested,
        timestamp = DateTime.parse(json['timestamp']);

  bool get isExpired {
    final now = DateTime.now();
    const expirationDuration = Duration(days: 1);
    return now.isAfter(timestamp.add(expirationDuration));
  }
}

class AnalyticsRequestsRepo {
  static final GetStorage _requestStorage =
      GetStorage('analytics_request_storage');

  static String _storageKey(String userId, LanguageModel language) {
    return 'analytics_request_${userId}_${language.langCodeShort}';
  }

  static RequestStatus? get(String userId, LanguageModel language) {
    final key = _storageKey(userId, language);
    final entry = _requestStorage.read(key);
    if (entry == null) {
      return null;
    }

    final status = _AnalyticsRequestEntry.fromJson(entry);
    if (status.isExpired) {
      _requestStorage.remove(key);
      return null;
    }

    return status.status;
  }

  static Future<void> set(
    String userId,
    LanguageModel language,
    RequestStatus status,
  ) async {
    final key = _storageKey(userId, language);
    final entry = _AnalyticsRequestEntry(
      status: status,
      timestamp: DateTime.now(),
    );
    await _requestStorage.write(key, entry.toJson());
  }

  static Future<void> remove(
    String userId,
    LanguageModel language,
  ) async {
    final key = _storageKey(userId, language);
    await _requestStorage.remove(key);
  }
}
