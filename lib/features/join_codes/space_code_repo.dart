import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/constants/local.key.dart';

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

  static String? get spaceCode {
    final String? code = _spaceStorage.read(PLocalKey.cachedSpaceCodeToJoin);
    if (code == null) return null;
    final int? writtenAt = _spaceStorage.read(
      PLocalKey.cachedSpaceCodeToJoinAt,
    );
    if (!isFresh(writtenAt, DateTime.now())) {
      clearSpaceCode();
      return null;
    }
    return code;
  }

  /// The activity id of a shared `/<uuid>` link ferried across the login
  /// bounce — same box, same TTL, same landing-retries-until-consumed
  /// contract as the join code above; consumed when the activity panel
  /// actually opens (LeftPanelActivityDetailsSubpage).
  static String? get activityId {
    final String? id = _spaceStorage.read(PLocalKey.cachedActivityToOpen);
    if (id == null) return null;
    final int? writtenAt = _spaceStorage.read(PLocalKey.cachedActivityToOpenAt);
    if (!isFresh(writtenAt, DateTime.now())) {
      clearActivityId();
      return null;
    }
    return id;
  }

  static Future<void> setActivityId(String id) async {
    if (id.isEmpty) return;
    await _spaceStorage.write(PLocalKey.cachedActivityToOpen, id);
    await _spaceStorage.write(
      PLocalKey.cachedActivityToOpenAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> clearActivityId() async {
    await _spaceStorage.remove(PLocalKey.cachedActivityToOpen);
    await _spaceStorage.remove(PLocalKey.cachedActivityToOpenAt);
  }

  static String? get recentCode =>
      _spaceStorage.read(PLocalKey.justInputtedCode);

  static Future<void> setSpaceCode(String code) async {
    if (code.isEmpty) return;
    await _spaceStorage.write(PLocalKey.cachedSpaceCodeToJoin, code);
    await _spaceStorage.write(
      PLocalKey.cachedSpaceCodeToJoinAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> setRecentCode(String code) async {
    await _spaceStorage.write(PLocalKey.justInputtedCode, code);
  }

  static Future<void> clearSpaceCode() async {
    await _spaceStorage.remove(PLocalKey.cachedSpaceCodeToJoin);
    await _spaceStorage.remove(PLocalKey.cachedSpaceCodeToJoinAt);
  }

  static Future<void> clearRecentCode() async {
    await _spaceStorage.remove(PLocalKey.justInputtedCode);
  }
}
