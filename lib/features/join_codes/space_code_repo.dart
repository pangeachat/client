import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';

/// The join-code box, which doubles as the **login-bounce ferry**: the
/// workspace location a logged-out visitor opened is cached here when they
/// are bounced to login, and re-entered by the `/` auth guard on the next
/// logged-in landing (PAuthGaurd; routing.instructions.md § A signed-out
/// visitor's destination). Two TTL-stamped entries ride it — the
/// [destination] itself, and the DM invite link's pending user id
/// ([dmInviteUserId]), which has its own consumer because it must act when
/// tapped logged in too.
class SpaceCodeRepo {
  static final GetStorage _spaceStorage = GetStorage('class_storage');

  /// How long a ferry entry stays actionable. A destination cached long ago
  /// must not carry a later login — possibly a different account on a shared
  /// browser — somewhere it never asked to go (#7524), so stale entries are
  /// ignored and cleared on read.
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

  /// Write an entry and its stamp so a concurrent read can only see BOTH or
  /// NEITHER. `GetStorage.write` applies the value to memory synchronously and
  /// then awaits a flush, so awaiting the value write before stamping leaves a
  /// window where the entry is readable with no stamp — which [_readFresh]
  /// scores as stale and CLEARS, destroying an entry that was merely mid-write.
  /// A native cold start opens exactly that window: the shell's DM-invite
  /// consumer mounts and reads the ferry while the invite route's redirect is
  /// still writing it, so the link landed on the chat list with the invite
  /// already wiped and did nothing until it was tapped again (#8555). Issuing
  /// both writes in one synchronous step (they apply to memory as they are
  /// called, before either flush is awaited) leaves no window to read into.
  static Future<void> _writeStamped(
    String key,
    String stampKey,
    String value,
  ) async {
    if (value.isEmpty) return;
    await Future.wait([
      _spaceStorage.write(key, value),
      _spaceStorage.write(stampKey, DateTime.now().millisecondsSinceEpoch),
    ]);
  }

  /// Clear both keys in one synchronous step, for the same reason
  /// [_writeStamped] writes them in one: a half-cleared entry is a readable
  /// state no reader should ever be able to observe.
  static Future<void> _clearStamped(String key, String stampKey) async {
    await Future.wait([
      _spaceStorage.remove(key),
      _spaceStorage.remove(stampKey),
    ]);
  }

  /// The workspace location ferried across the login bounce, exactly as the
  /// router resolved it (`/?<query>`), or null. Written by the bounce and
  /// consumed — read and cleared in one step — by the same guard's logged-in
  /// landing (PAuthGaurd); a brand-new user's onboarding reads a join code
  /// out of it first (ClientCourseProvider). A stored value that is not a
  /// valid destination ([isValidDestination]) reads as absent and is cleared:
  /// the bounce may never send anyone off the app.
  static String? get destination {
    final location = _readFresh(
      PLocalKey.cachedDestination,
      PLocalKey.cachedDestinationAt,
    );
    if (location == null) return null;
    if (isValidDestination(location)) return location;
    _clearStamped(PLocalKey.cachedDestination, PLocalKey.cachedDestinationAt);
    return null;
  }

  static Future<void> setDestination(String location) => _writeStamped(
    PLocalKey.cachedDestination,
    PLocalKey.cachedDestinationAt,
    location,
  );

  static Future<void> clearDestination() =>
      _clearStamped(PLocalKey.cachedDestination, PLocalKey.cachedDestinationAt);

  /// Whether [location] is somewhere the ferry may carry a login: a workspace
  /// URL — the world root with a non-empty query — and nothing else. The bare
  /// root is the default landing, so there is nothing to keep (and caching it
  /// would let a plain app open, or the native SSO callback, overwrite a real
  /// destination); any other path, and any absolute URL, is refused so the
  /// post-login redirect can only ever land inside the app. Pure —
  /// unit-tested (login_bounce_destination_test.dart).
  static bool isValidDestination(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null) return false;
    return !uri.hasScheme &&
        !uri.hasAuthority &&
        uri.path == PRoutes.world &&
        uri.query.isNotEmpty;
  }

  /// The user id of a DM invite link (`/invite_user/<id>`) — its own entry,
  /// same box, same TTL; cached by the invite route's redirect on every
  /// landing (not only the login bounce, #8436) and consumed from inside the
  /// shell once the DM has actually opened (or definitively failed to),
  /// DmInviteController.consumePending.
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
