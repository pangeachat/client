import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';

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
    if (segments.length >= 3 &&
        segments.first == 'courses' &&
        segments[1].startsWith('!') &&
        segments[2].startsWith('!')) {
      // A room inside a course, optionally on a sub-page (search / details /
      // details/<management> / invite): the course stays the map filter; the
      // room rides as a left `room:<id>/<sub>` push beside it. See
      // `routing.instructions.md`.
      final roomParam = segments.length == 3
          ? segments[2]
          : '${segments[2]}/${segments.sublist(3).join('/')}';
      return _toCourseWorkspace(uri, segments[1], roomParam);
    }
    // Deep course-management pages are FLAT pushes on the `course` token:
    // /courses/:spaceid/<page> → ?m=course:spaceid&left=course:<page> (edit,
    // invite, access, permissions, emotes, addcourse). The 3rd segment is a
    // literal page (not a `!room`, handled above). The legacy `/details` shim is
    // stripped: bare `/details` → the card; `/details/<page>` → the page. The
    // Completer-carrying `addcourse/:courseId` flow (4 segs, not `details`) is
    // left route-driven, so it falls through. See `routing.instructions.md`.
    if (segments.length == 3 &&
        segments.first == 'courses' &&
        segments[1].startsWith('!') &&
        !segments[2].startsWith('!')) {
      return segments[2] == 'details'
          ? _toCourseWorkspace(uri, segments[1], null)
          : _toCourseWorkspaceWithPage(uri, segments[1], segments[2]);
    }
    if (segments.length == 4 &&
        segments.first == 'courses' &&
        segments[1].startsWith('!') &&
        segments[2] == 'details') {
      return _toCourseWorkspaceWithPage(uri, segments[1], segments[3]);
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
      return tab == null
          ? null
          : '/?right=${PanelToken('analytics', tab).encode()}';
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

    // world_v2: a bare room and its sub-pages render as a `room` token over the
    // world map — not a `/rooms/:roomid` route. A room id starts with `!`; the
    // sub-page tail (search / details / details/<management> / invite) rides the
    // token param, and `?event=`/`?body=`/`?filter=` survive. This is the
    // inbound contract for matrix.to / push / share links we don't control;
    // literal fork segments (`archive`, `newprivatechat`, …) don't start with
    // `!`, so they fall through to the switch and stay route-driven. See
    // `routing.instructions.md`.
    if (rest.isNotEmpty && rest.first.startsWith('!')) {
      return _toRoomToken(uri, rest.first, rest.sublist(1));
    }

    // Bare `/rooms` was the old chats home. world_v2 has no `/chats` route — the
    // chat list is the `chats` left token over the world map — so map it straight
    // there in one hop. The earlier `/rooms` → `/chats` → `/?left=chats` chain
    // briefly emitted the dead `/chats` literal (the bug in #7067).
    if (rest.isEmpty) return _toRootWithLeftToken(uri, 'chats');

    final List<String>? target = switch (rest) {
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

  /// Rewrite a bare-room legacy path (`/rooms/:roomid[/sub]`) to a `room`
  /// token over the world map (`/?left=room:id[/sub]`). The sub-page tail
  /// (search / details / details/management / invite) rides the token param;
  /// every other query (`event`, `body`, `filter`, an open `right=`) is kept,
  /// while any prior `left=`/`m=` is dropped (this navigation IS the room). The
  /// result has no `/rooms` path segment, so it never re-fires.
  static String _toRoomToken(Uri uri, String roomId, List<String> tail) {
    final param = tail.isEmpty ? roomId : '$roomId/${tail.join('/')}';
    // Keep every prior query EXCEPT a previous left list / course filter (this
    // navigation IS the room), and seat the new room token first.
    final kept = WorkspaceQuery.parts(uri.query);
    WorkspaceQuery.removeKeys(kept, {'left', 'm'});
    final parts = ['left=${PanelToken('room', param).encode()}', ...kept];
    return '${PRoutes.world}?${parts.join('&')}';
  }

  /// Rewrite a legacy course path to the world_v2 workspace form: the course as
  /// a `?m=course:<spaceid>` map filter plus a left `course` panel, with [room]
  /// (when present) added as the live `room` token beside it. Any other query
  /// the legacy URL carried (`activity=`, `event=`, an existing `right=`/`left=`)
  /// is preserved; the path becomes the world map `/`. Idempotent: the result
  /// has no `courses` path segment, so the course arms never re-fire.
  static String _toCourseWorkspace(Uri uri, String space, String? room) {
    final parts = WorkspaceQuery.parts(uri.query);

    // Lift out any existing left list (keep tokens already there) and drop the
    // prior `left=`/`m=` so the course filter + left can be rebuilt cleanly.
    final leftValue = WorkspaceQuery.valueOf(uri.query, 'left') ?? '';
    WorkspaceQuery.removeKeys(parts, {'left', 'm'});

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

  /// Like [_toCourseWorkspace] but for a deep course-management PAGE: the course
  /// card stays the `course` master and the page opens beside it as a
  /// `coursepage` detail (`left=course,coursepage:<page>`), over the
  /// `?m=course:<space>` filter — the same master/detail the in-app buttons
  /// produce, so a deep link lands identically. Any prior `coursepage` token is
  /// replaced; other left tokens and query are kept. See `routing.instructions.md`.
  static String _toCourseWorkspaceWithPage(Uri uri, String space, String page) {
    final parts = WorkspaceQuery.parts(uri.query);
    final leftValue = WorkspaceQuery.valueOf(uri.query, 'left') ?? '';
    WorkspaceQuery.removeKeys(parts, {'left', 'm'});

    final left = leftValue
        .split(',')
        .where(
          (e) =>
              e.isNotEmpty && e != 'coursepage' && !e.startsWith('coursepage:'),
        )
        .toList();
    if (!left.any((e) => e == 'course' || e.startsWith('course:'))) {
      left.insert(0, 'course');
    }
    left.add(PanelToken('coursepage', page).encode());

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
    final parts = WorkspaceQuery.parts(uri.query);
    // Hand-rolled (not valueOf/removeKeys): this upserts [type] INTO the existing
    // left list IN PLACE, preserving the param's position. The drop-and-append
    // helpers would move `left=` to the end of the query. See WorkspaceQuery.
    final idx = parts.indexWhere((p) => p == 'left' || p.startsWith('left='));
    if (idx >= 0) {
      final eq = parts[idx].indexOf('=');
      final value = eq >= 0 ? parts[idx].substring(eq + 1) : '';
      final present = value
          .split(',')
          .any((e) => e == type || e.startsWith('$type:'));
      if (!present) {
        parts[idx] = 'left=${value.isEmpty ? type : '$value,$type'}';
      }
    } else {
      parts.add('left=$type');
    }
    return WorkspaceQuery.location(PRoutes.world, parts);
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
}
