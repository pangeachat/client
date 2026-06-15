import 'package:fluffychat/features/navigation/route_paths.dart';

/// Permanent redirect shims from pre-world_v2 `/rooms/...` section paths
/// to their first-class roots, so bookmarks, cached join intents, and
/// in-flight push notifications keep working forever.
///
/// Wired as the router's single top-level redirect. Pure and synchronous:
/// returns the rewritten location, or null to leave the route alone.
/// Matrix rooms themselves (`/rooms/:roomid`) are NOT legacy — they stay.
abstract class LegacyRedirects {
  /// Map an incoming location to its world_v2 equivalent, or null.
  static String? resolve(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty || segments.first != 'rooms') return null;

    final rest = segments.sublist(1);

    // The retired nested activity route `/rooms/spaces/:spaceid/activity/:id`
    // (old push notifications, bookmarks) → the canonical in-course overlay
    // `/courses/:spaceid?activity=:id`, preserving roomid/launch/tab. The space
    // id is kept so the activity opens in its course even for a user who has
    // not yet joined it. Must precede the generic `spaces` arm below, which
    // would otherwise rebuild the deleted nested path.
    if (rest.length >= 4 && rest[0] == 'spaces' && rest[2] == 'activity') {
      final query = <String, String>{
        'activity': rest[3],
        ...uri.queryParameters,
      };
      final qs = query.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');
      return '/courses/${Uri.encodeComponent(rest[1])}?$qs';
    }

    final List<String>? target = switch (rest) {
      // `/rooms` — the old chats root. Chats now live at `/chats`; the
      // world map is `/`.
      [] => const ['chats'],

      // Renamed sections.
      ['user_home', ...final tail] => ['profile', ...tail],
      ['analytics', ...final tail] => ['analytics', ...tail],
      ['settings', ...final tail] => ['settings', ...tail],

      // Find/create-course flows keep their literal names under /courses;
      // the old public-preview catch-all gets a literal prefix so it can
      // never collide with `/courses/:spaceid`.
      ['course'] => const ['courses'],
      ['course', 'private', ...final tail] => ['courses', 'private', ...tail],
      ['course', 'own', ...final tail] => ['courses', 'own', ...tail],
      ['course', final roomId, ...final tail] => [
        'courses',
        'preview',
        roomId,
        ...tail,
      ],

      // Joined course spaces: `/rooms/spaces/:spaceid/...` →
      // `/courses/:spaceid/...`.
      ['spaces', ...final tail] => ['courses', ...tail],

      // Anything else under /rooms (e.g. an actual room id, archive,
      // newgroup) is fork-owned and stays put.
      _ => null,
    };
    if (target == null) return null;

    // pathSegments are percent-decoded; re-encode so ids with reserved
    // characters survive the rewrite intact.
    final path = '/${target.map(Uri.encodeComponent).join('/')}';
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }

  /// go_router top-level redirect signature adapter.
  static String? handle(Uri uri) {
    final resolved = resolve(uri);
    // Never redirect to the location we are already at.
    if (resolved == null || resolved == uri.toString()) return null;
    return resolved;
  }

  /// Guard: bare `/rooms` maps to the chats list.
  // (Handled by the `[] => const ['chats']` arm above.)
  static String get chatsHome => PRoutes.chats;
}
