import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/constants/local.key.dart';

/// The join-code box, which doubles as the **login-bounce ferry**: an inbound
/// link's payload is cached here when a logged-out visitor is bounced to
/// login, and re-entered by the `/` auth guard on the next logged-in landing
/// (PAuthGaurd). Three payloads ride it — a course join code, a shared
/// activity id, and a DM invite user id — each a TTL-stamped entry with the
/// same landing-retries-until-consumed contract; who consumes each is noted
/// on its getter.
class SpaceCodeRepo {
  static final GetStorage _spaceStorage = GetStorage('class_storage');

  /// How long a cached join code stays actionable. An inbound join link's
  /// code is ferried through this cache across the login bounce (#7524); a
  /// code cached long ago must not surprise-join a later login, possibly by
  /// a different account on a shared browser, so stale entries are ignored
  /// and cleared on read.
  static const Duration cacheTTL = Duration(hours: 1);

  /// Whether a cache entry stamped [writtenAtMillis] is still actionable at
  /// [now]. A missing stamp (an entry written before the TTL existed) counts
  /// as stale. Pure — unit-tested against the TTL boundary.
  static bool isFresh(int? writtenAtMillis, DateTime now) =>
      writtenAtMillis != null &&
      now.difference(DateTime.fromMillisecondsSinceEpoch(writtenAtMillis)) <=
          cacheTTL;

  /// Read a TTL-stamped ferry entry; a stale one is cleared and reads as
  /// absent.
  static String? _readFresh(String key, String stampKey) {
    final String? value = _spaceStorage.read(key);
    if (value == null) return null;
    final int? writtenAt = _spaceStorage.read(stampKey);
    if (!isFresh(writtenAt, DateTime.now())) {
      _clearStamped(key, stampKey);
      return null;
    }
    return value;
  }

  static Future<void> _writeStamped(
    String key,
    String stampKey,
    String value,
  ) async {
    if (value.isEmpty) return;
    await _spaceStorage.write(key, value);
    await _spaceStorage.write(stampKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> _clearStamped(String key, String stampKey) async {
    await _spaceStorage.remove(key);
    await _spaceStorage.remove(stampKey);
  }

  /// The course join code ferried across the login bounce; consumed by the
  /// join page's actually-firing submit (CourseCodePage) or, for a brand-new
  /// user, by onboarding.
  static String? get spaceCode => _readFresh(
    PLocalKey.cachedSpaceCodeToJoin,
    PLocalKey.cachedSpaceCodeToJoinAt,
  );

  static Future<void> setSpaceCode(String code) => _writeStamped(
    PLocalKey.cachedSpaceCodeToJoin,
    PLocalKey.cachedSpaceCodeToJoinAt,
    code,
  );

  static Future<void> clearSpaceCode() => _clearStamped(
    PLocalKey.cachedSpaceCodeToJoin,
    PLocalKey.cachedSpaceCodeToJoinAt,
  );

  /// The activity id of a shared `/<uuid>` link ferried across the login
  /// bounce — same box, same TTL, same landing-retries-until-consumed
  /// contract as the join code above; consumed when the activity panel
  /// actually opens (LeftPanelActivityDetailsSubpage).
  static String? get activityId => _readFresh(
    PLocalKey.cachedActivityToOpen,
    PLocalKey.cachedActivityToOpenAt,
  );

  static Future<void> setActivityId(String id) => _writeStamped(
    PLocalKey.cachedActivityToOpen,
    PLocalKey.cachedActivityToOpenAt,
    id,
  );

  static Future<void> clearActivityId() => _clearStamped(
    PLocalKey.cachedActivityToOpen,
    PLocalKey.cachedActivityToOpenAt,
  );

  /// The user id of a DM invite link (`/invite_user/<id>`) ferried across the
  /// login bounce (#8436) — same box, same TTL, same contract; consumed by
  /// the invite landing once it has actually opened the DM (or definitively
  /// failed to), DmInviteLandingPage.
  static String? get dmInviteUserId => _readFresh(
    PLocalKey.cachedDmInviteUserId,
    PLocalKey.cachedDmInviteUserIdAt,
  );

  static Future<void> setDmInviteUserId(String userId) => _writeStamped(
    PLocalKey.cachedDmInviteUserId,
    PLocalKey.cachedDmInviteUserIdAt,
    userId,
  );

  static Future<void> clearDmInviteUserId() => _clearStamped(
    PLocalKey.cachedDmInviteUserId,
    PLocalKey.cachedDmInviteUserIdAt,
  );

  static String? get recentCode =>
      _spaceStorage.read(PLocalKey.justInputtedCode);

  static Future<void> setRecentCode(String code) async {
    await _spaceStorage.write(PLocalKey.justInputtedCode, code);
  }

  static Future<void> clearRecentCode() async {
    await _spaceStorage.remove(PLocalKey.justInputtedCode);
  }
}
