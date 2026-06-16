import 'package:fluffychat/widgets/matrix.dart';

/// Room/space ids ride world_v2 URLs as bare localparts (`!abc`) instead of the
/// full Matrix id (`!abc:home.server`), so links read cleanly. The home
/// server_name is assumed when absent and re-attached before any
/// `getRoomById`. Federation-safe: ids from another homeserver always carry
/// their own `:domain`, so they are never shortened and never get the home
/// domain attached.
///
/// `shortRoomId` is used where URLs are built (the PRoutes builders);
/// `fullRoomId` where a URL room-id param is read back (routes.dart page
/// builders, route_facts). See `routing.instructions.md`.

/// The logged-in user's server_name, or null if unavailable (pre-login / tests
/// that never exercise the global). Read lazily so URL helpers stay independent
/// of any init order.
String? get _homeDomain {
  try {
    final userId = MatrixState.pangeaController.matrixState.client.userID;
    final i = userId?.indexOf(':') ?? -1;
    return i == -1 ? null : userId!.substring(i + 1);
  } catch (_) {
    // Global not ready (e.g. before login): fall back to leaving ids full.
    return null;
  }
}

/// Drop the home server_name so an id can ride a URL as a bare localpart. Ids
/// from another homeserver, or any id whose domain isn't the home domain, are
/// returned unchanged (still federation-resolvable). [domain] overrides the
/// home domain (for tests).
String shortRoomId(String id, {String? domain}) {
  final d = domain ?? _homeDomain;
  if (d != null && id.endsWith(':$d')) {
    return id.substring(0, id.length - d.length - 1);
  }
  return id;
}

/// Re-attach the home server_name to a URL room-id param. A segment that
/// already has a `:domain` (a foreign-homeserver id, or an untouched full id)
/// is returned unchanged. [domain] overrides the home domain (for tests).
String fullRoomId(String segment, {String? domain}) {
  if (segment.isEmpty || segment.contains(':')) return segment;
  final d = domain ?? _homeDomain;
  return d == null ? segment : '$segment:$d';
}

/// Strip the home server_name from every `!localpart:home` room id in a URL
/// string (path and query), leaving foreign-homeserver ids intact. Applied by
/// the router redirect so room URLs display as bare localparts regardless of how
/// they were built — including upstream/fork navigation we don't route through
/// [PRoutes]. Keeps upstream files untouched (clean cherry-picks). [domain]
/// overrides the home domain (for tests).
String shortenHomeRoomIdsInUrl(String location, {String? domain}) {
  final d = domain ?? _homeDomain;
  if (d == null) return location;
  return location.replaceAllMapped(
    RegExp('(![^:/?&#]+):${RegExp.escape(d)}'),
    (m) => m.group(1)!,
  );
}
