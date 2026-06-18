import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
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

    // world_v2: the profile + settings tree is a right-column panel, not a
    // route. Rewrite any /settings or /profile location to the canonical
    // `settings` token so deep links, bookmarks, and the retired route-driven
    // render all land on the panel. The token param is the sub-page (a
    // profile/* path keeps its `profile/` prefix so `/profile/edit` is
    // distinguishable). See `routing.instructions.md`.
    if (segments.isNotEmpty &&
        (segments.first == 'settings' || segments.first == 'profile')) {
      final sub = segments.first == 'profile'
          ? (segments.length > 1
              ? 'profile/${segments.sublist(1).join('/')}'
              : '')
          : segments.sublist(1).join('/');
      // world_v2 master/detail: the menu is the `settings` master; a sub-page
      // opens beside it as a `settingspage` detail (front of the right group,
      // menu kept). A bare /settings or /profile is just the menu.
      final menu = const PanelToken('settings').encode();
      if (sub.isEmpty) return '/?right=$menu';
      return '/?right=${PanelToken('settingspage', sub).encode()},$menu';
    }

    // world_v2: section roots are token-driven and the path always collapses to
    // `/` — section identity rides in the left token (read by `sectionFor`), not
    // the path. The legacy `/chats` list and the bare `/courses` add-course hub
    // each become a left token over `/`; analytics collapses to its right-column
    // summary token. These re-resolve to null once at `/` (no path segment to
    // match), so they never loop. See `routing.instructions.md`.
    if (segments.length == 1 && segments.first == 'chats') {
      return _toRootWithLeftToken(uri, 'chats');
    }
    // The bare `/courses` add-course hub → a bare `addcourse` left token (the
    // hub chooser; its steps are `addcourse:own` etc.). Length-1 so it never
    // collides with the `/courses/:spaceid` or `/courses/own` arms below.
    if (segments.length == 1 && segments.first == 'courses') {
      return _toRootWithLeftToken(uri, 'addcourse');
    }
    // world_v2: a joined course is a map filter (`?m=course:<id>`) over the
    // world map plus a left `course` panel — not a `/courses/:spaceid` route.
    // The bare course path (and any query it carries, e.g. ?activity=) maps to
    // the filter + course panel; a course room (`/courses/:spaceid/:roomid`)
    // adds the room as a left token beside the course (closing it reveals the
    // course again). Deeper management paths (`details/…`, `addcourse/…`, whose
    // 3rd segment is a literal, not a `!room`) are left route-driven. See
    // `routing.instructions.md`.
    if (segments.length == 2 &&
        segments.first == 'courses' &&
        segments[1].startsWith('!')) {
      return _toCourseWorkspace(uri, segments[1], null);
    }
    if (segments.length == 3 &&
        segments.first == 'courses' &&
        segments[1].startsWith('!') &&
        segments[2].startsWith('!')) {
      return _toCourseWorkspace(uri, segments[1], segments[2]);
    }
    // The add-course wizard's first step renders as a left-column panel; rewrite
    // its literal path to the `addcourse` token, preserving the flow's query
    // (lang/showAll). Deeper steps (/courses/own/:courseid …) stay route-driven.
    if (segments.length == 2 &&
        segments.first == 'courses' &&
        const {'own', 'browse', 'private'}.contains(segments[1])) {
      final token = PanelToken('addcourse', segments[1]).encode();
      return uri.query.isEmpty ? '/?left=$token' : '/?left=$token&${uri.query}';
    }
    if (segments.isNotEmpty && segments.first == 'analytics') {
      // Each analytics metric maps to its right-column summary tab. An unknown
      // sub (a future route-driven view) is left alone so it still renders.
      const tabs = {
        '': 'vocab',
        'vocab': 'vocab',
        'morph': 'grammar',
        'activities': 'sessions',
        'level': 'level',
      };
      final tab = tabs[segments.length > 1 ? segments[1] : ''];
      return tab == null ? null : '/?right=${PanelToken('analytics', tab).encode()}';
    }

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

  /// Rewrite a legacy course path to the world_v2 workspace form: the course as
  /// a `?m=course:<spaceid>` map filter plus a left `course` panel, with [room]
  /// (when present) added as the live `room` token beside it. Any other query
  /// the legacy URL carried (`activity=`, `event=`, an existing `right=`/`left=`)
  /// is preserved; the path becomes the world map `/`. Idempotent: the result
  /// has no `courses` path segment, so the course arms never re-fire.
  static String _toCourseWorkspace(Uri uri, String space, String? room) {
    final parts = uri.query.isEmpty ? <String>[] : uri.query.split('&');

    // Lift out any existing left list (keep tokens already there) and drop any
    // prior `m=` so the course filter can be set cleanly.
    var leftValue = '';
    final li = parts.indexWhere((p) => p == 'left' || p.startsWith('left='));
    if (li >= 0) {
      final eq = parts[li].indexOf('=');
      leftValue = eq >= 0 ? parts[li].substring(eq + 1) : '';
      parts.removeAt(li);
    }
    parts.removeWhere((p) => p == 'm' || p.startsWith('m='));

    final left = leftValue.split(',').where((e) => e.isNotEmpty).toList();
    if (!left.any((e) => e == 'course' || e.startsWith('course:'))) {
      left.insert(0, 'course');
    }
    if (room != null) {
      // One live room: drop any other room token, then seat this one.
      left.removeWhere((e) => e == 'room' || e.startsWith('room:'));
      left.add(PanelToken('room', room).encode());
    }

    final query = <String>[
      'm=${PanelToken('course', space).encode()}',
      'left=${left.join(',')}',
      ...parts,
    ];
    return '/?${query.join('&')}';
  }

  /// Rewrite a legacy section root to the world path `/` with a `left=<type>`
  /// token, adding the token if absent and **dropping the legacy path** (the
  /// path always collapses to `/`; section identity rides in the token, read by
  /// `sectionFor`). Every other query param is preserved. Idempotent: the result
  /// has no path segment, so the section arms never re-fire (no loop).
  static String _toRootWithLeftToken(Uri uri, String type) {
    final parts = uri.query.isEmpty ? <String>[] : uri.query.split('&');
    final idx =
        parts.indexWhere((p) => p == 'left' || p.startsWith('left='));
    if (idx >= 0) {
      final eq = parts[idx].indexOf('=');
      final value = eq >= 0 ? parts[idx].substring(eq + 1) : '';
      final present =
          value.split(',').any((e) => e == type || e.startsWith('$type:'));
      if (!present) {
        parts[idx] = 'left=${value.isEmpty ? type : '$value,$type'}';
      }
    } else {
      parts.add('left=$type');
    }
    return parts.isEmpty
        ? PRoutes.world
        : '${PRoutes.world}?${parts.join('&')}';
  }

  /// go_router top-level redirect signature adapter. After any legacy rewrite,
  /// strip the home server_name from room ids so URLs display as bare
  /// localparts (`/rooms/!abc` not `/rooms/!abc:home`), regardless of how the
  /// location was built. The read side re-attaches the domain (see
  /// room_id_url.dart), so this is display-only.
  static String? handle(Uri uri) {
    final candidate = resolve(uri) ?? uri.toString();
    final shortened = shortenHomeRoomIdsInUrl(candidate);
    // Never redirect to the location we are already at.
    return shortened == uri.toString() ? null : shortened;
  }

  /// Guard: bare `/rooms` maps to the chats list.
  // (Handled by the `[] => const ['chats']` arm above.)
  static String get chatsHome => PRoutes.chats;
}
