import 'package:get_storage/get_storage.dart';

/// Per-device record of activities this user has already rated, so the
/// post-play prompt doesn't reappear after a submitted rating.
///
/// Keyed by activity id, storing the pinned version the rating was made
/// against: a session pinned to a DIFFERENT version re-prompts (the server
/// upserts one opinion per (user, activity), so the resubmission simply
/// overwrites the previous one). Per-device only — a duplicate prompt on
/// another device is harmless for the same reason.
///
/// Reads are synchronous; the box is opened at app startup (main.dart's
/// GetStorage init block).
class ActivityRatingStore {
  static const String storageKey = 'activity_rating_storage';
  static final GetStorage _storage = GetStorage(storageKey);

  static const String _versionKey = 'version';
  static const String _ratedAtKey = 'rated_at';

  /// Whether this activity was already rated at [versionId] on this device.
  /// A null [versionId] (legacy embedded-plan room) matches only a rating
  /// that was also made with no version.
  static bool hasRated(String activityId, String? versionId) {
    final stored = _storage.read(activityId);
    if (stored is! Map) return false;
    return stored[_versionKey] == versionId;
  }

  static Future<void> markRated(String activityId, String? versionId) =>
      _storage.write(activityId, {
        _versionKey: versionId,
        _ratedAtKey: DateTime.now().toIso8601String(),
      });
}
