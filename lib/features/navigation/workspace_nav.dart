import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';

/// Builds workspace location strings by adding or removing panel tokens on the
/// current URL, preserving the path and every other query param. The URL is the
/// single source of truth for which panels are open (see
/// `routing.instructions.md`), so every open/close routes through here and then
/// `context.go(...)` rather than mutating app-state.
///
/// The raw query is reassembled by hand instead of via `Uri.replace`'s
/// `queryParameters`, which would percent-encode a second time and corrupt a
/// token whose param is already encoded (an encoded construct's `%7B` etc.).
abstract class WorkspaceNav {
  /// The last URL the router resolved to, so [preserveOpenPanels] can tell a
  /// left-navigation (a path change) from a panel open/close (a same-path query
  /// change). go_router's redirect only sees the destination, so the previous
  /// URL has to be remembered here.
  static Uri? _lastResolvedUri;

  /// Keep the open RIGHT panels across navigation. The right column is the
  /// learner's persistent companion (analytics, a detail, a review), so a
  /// section navigation — a path change whose destination doesn't itself name
  /// panels — carries the previous `right=` list forward instead of dropping it
  /// (which is what a bare `context.go('/path')` would do). The `left=` list is
  /// section *content* and is deliberately NOT carried: moving to a new section
  /// shows that section (its `_MainView`/default), not the prior section's left
  /// panels. Opening or closing a panel is a same-path query change and is left
  /// exactly as written. Wired as the router's top-level redirect; returns a
  /// rewritten location or null to accept as-is.
  static String? preserveOpenPanels(Uri destination) {
    final last = _lastResolvedUri;
    // The world map is home: arriving at it with no panels of its own is a
    // deliberate clear-all (the World control), so never carry the right-column
    // companions forward onto it. See `routing.instructions.md`.
    if (destination.path == PRoutes.world && destination.query.isEmpty) {
      _lastResolvedUri = destination;
      return null;
    }
    final namesPanels = destination.query.split('&').any(
          (p) =>
              p == 'right' ||
              p == 'left' ||
              p.startsWith('right=') ||
              p.startsWith('left='),
        );
    // No history yet, an explicit panel set, or a same-path change → accept.
    if (last == null || namesPanels || destination.path == last.path) {
      _lastResolvedUri = destination;
      return null;
    }
    final carried = last.query
        .split('&')
        .where((p) => p.startsWith('right='))
        .toList();
    if (carried.isEmpty) {
      _lastResolvedUri = destination;
      return null;
    }
    final query = [
      if (destination.query.isNotEmpty) destination.query,
      ...carried,
    ].join('&');
    final target = '${destination.path}?$query';
    // Record the rewritten target so the redirect re-run accepts it (same path).
    _lastResolvedUri = Uri.parse(target);
    return target;
  }

  /// Add [token] to the `left` list (deduped). [atStart] places it at the left
  /// edge of the column rather than the inside.
  static String openLeft(Uri current, PanelToken token, {bool atStart = false}) =>
      _mutate(current, 'left', (tokens) => _add(tokens, token, atStart));

  /// Open (or replace) a DETAIL panel, enforcing the registry's **sibling**
  /// groups across BOTH columns: any open token that shares a sibling group with
  /// [token] is dropped (siblings can't coexist — one live view; one "zoom"
  /// detail across columns; see [PanelDef.siblingGroups]). The token seats in its
  /// own column — a right detail blooms at the front (left of its master); a left
  /// detail appends (after the list/course it details). This is the one
  /// generalized detail open; the named helpers below delegate to it. See
  /// `routing.instructions.md`.
  static String openDetail(Uri current, PanelToken token) {
    final col = PanelRegistry.defFor(token.type)?.column ?? PanelColumn.left;
    return _mutateBoth(
      current,
      (left) => _placeDetail(left, token, PanelColumn.left, col),
      (right) => _placeDetail(right, token, PanelColumn.right, col),
    );
  }

  /// Drop siblings (and the token itself, for dedup) from one column's list,
  /// then seat [token] only if it belongs to [thisCol] (front for right, end for
  /// left). The other column just sheds siblings.
  static List<PanelToken> _placeDetail(
    List<PanelToken> tokens,
    PanelToken token,
    PanelColumn thisCol,
    PanelColumn tokenCol,
  ) {
    final next =
        tokens.where((t) => t != token && !_areSiblings(token, t)).toList();
    if (thisCol == tokenCol) {
      thisCol == PanelColumn.right ? next.insert(0, token) : next.add(token);
    }
    return next;
  }

  /// True when [a] and [b] are **siblings** — they share any sibling group (per
  /// the registry), so they can't coexist and one replaces the other.
  static bool _areSiblings(PanelToken a, PanelToken b) {
    final ga = PanelRegistry.defFor(a.type)?.siblingGroups ?? const <String>{};
    final gb = PanelRegistry.defFor(b.type)?.siblingGroups ?? const <String>{};
    return ga.any(gb.contains);
  }

  /// A live room (chat) is a left detail in the `liveView` group, so opening one
  /// drops any other room/session and leaves the right column untouched.
  static String openExclusiveLeftRoom(Uri current, PanelToken token) =>
      openDetail(current, token);

  /// A completed-activity `session` review is a left detail in BOTH `liveView`
  /// and `detail`, so opening it drops any other room/session AND any
  /// vocab/grammar detail (one detail across columns).
  static String openExclusiveSession(Uri current, PanelToken token) =>
      openDetail(current, token);

  /// Open a vocab/grammar construct detail (the `detail` group): drops the other
  /// construct detail and any `session`, seats the detail at the front of the
  /// right group, and ensures its pinned `analytics` summary master exists
  /// (seated at [summaryTab] from a cold start). See `routing.instructions.md`.
  static String openConstructDetail(
    Uri current,
    PanelToken detail,
    String summaryTab,
  ) =>
      _mutateBoth(
        current,
        (left) => left.where((t) => !_areSiblings(detail, t)).toList(),
        (right) {
          final next =
              right.where((t) => t != detail && !_areSiblings(detail, t)).toList();
          next.insert(0, detail);
          if (!next.any((t) => t.type == 'analytics')) {
            next.add(PanelToken('analytics', summaryTab));
          }
          return next;
        },
      );

  /// Open a practice session as a right-column panel that **takes over the
  /// analytics surface**: it clears the analytics master and any vocab/grammar
  /// detail on the right (and a left `session` review — practice shares the one
  /// "detail" slot across columns), then seats `practice:<type>` at the front.
  /// While practice is open no vocab/grammar list or detail can be viewed —
  /// opening one drops practice (the registry `detail` group), and tapping the
  /// cluster's analytics replaces the whole right column. Practice is a normal
  /// bounded panel, not a route or a fullscreen surface. See
  /// `routing.instructions.md`.
  static String openPractice(Uri current, String type) => _mutateBoth(
        current,
        (left) => left.where((t) => t.type != 'session').toList(),
        (right) {
          final next = right
              .where((t) =>
                  t.type != 'analytics' &&
                  t.type != 'vocab' &&
                  t.type != 'grammar' &&
                  t.type != 'practice')
              .toList();
          next.insert(0, PanelToken('practice', type));
          return next;
        },
      );

  /// Switch the workspace to course [spaceId]: set the `?m=course:<id>` map
  /// filter AND a `course` left panel (at [tab] in its param if given),
  /// replacing any prior course filter/token. Keeps the chat list, the right
  /// column, and every other query. This is the token-native "open this course
  /// from anywhere" used when navigating to a course outside its current filter
  /// (joins, activity-session returns) — the tab must ride the token param, so a
  /// bare `?tab=` query cannot express it. See `routing.instructions.md`.
  static String openCourseFilter(Uri current, String spaceId, {String? tab}) {
    final lists = parseOpenPanels(current);
    final left = <PanelToken>[
      PanelToken('course', tab),
      // Drop any prior course token, the Courses launcher (`addcourse`), and a
      // stale management page (`coursepage`) — picking a specific course replaces
      // the launcher rather than stacking beside it, and a coursepage left from
      // the previous course would silently re-target the new one.
      ...lists.left.where((t) =>
          t.type != 'course' && t.type != 'addcourse' && t.type != 'coursepage'),
    ];
    final parts = current.query.isEmpty ? <String>[] : current.query.split('&');
    parts.removeWhere(
      (p) =>
          p == 'm' ||
          p.startsWith('m=') ||
          p == 'left' ||
          p.startsWith('left='),
    );
    final query = <String>[
      'm=${PanelToken('course', shortRoomId(spaceId)).encode()}',
      'left=${left.map((t) => t.encode()).join(',')}',
      ...parts,
    ];
    return '${PRoutes.world}?${query.join('&')}';
  }

  /// Open (or re-tab) a `course` panel at the left edge, replacing any existing
  /// course token. The course's identity is the `?m=course:<id>` map filter
  /// (read via activeSpaceIdFor), not the token — the token's param is just the
  /// active tab, so switching tabs is opening the course token with a new tab
  /// (the `m` filter is preserved by `_mutate`). A live room and the chat list
  /// are kept (a course can scope a room). See `routing.instructions.md`.
  static String openCourse(Uri current, PanelToken token) =>
      _mutate(current, 'left', (tokens) {
        final next = tokens.where((t) => t.type != 'course').toList();
        next.insert(0, token);
        return next;
      });

  /// Open a course-management page (invite / edit / access / permissions /
  /// emotes / change-course) as the course card's DETAIL — a `coursepage` panel
  /// beside the `course` master that coexists when width allows and folds to a
  /// push when not, mirroring settings menu→page ([openSettings]). The card's
  /// space rides in the `?m=course:<id>` filter (preserved here), so the page
  /// param is just the page id. One management page at a time (the registry
  /// `coursepage` exclusive group drops any prior one). See
  /// `routing.instructions.md`.
  static String openCoursePage(Uri current, String page) =>
      openDetail(current, PanelToken('coursepage', page));

  /// Replace the whole `left` list (e.g. tapping a top-level section: Chats,
  /// the avatar/profile). The `right` list and other query params are preserved.
  static String setLeft(Uri current, List<PanelToken> tokens) =>
      _mutate(current, 'left', (_) => tokens);

  /// Navigate to a section (`/chats`, `/courses/:id`, `/profile`, or the world
  /// map `/`), setting [section] as the sole section panel while **keeping the
  /// live room and the right column** — so navigating between sections changes
  /// which panel is focused instead of tearing the open chat down ("move to the
  /// world and keep the chat"; see `routing.instructions.md`). Pass `null` for
  /// the world map (no section panel). The section sits to the left of the room
  /// so a list/detail reads left-to-right. Set [keepRoom] false for a focused
  /// full-bleed flow (the add-course hub) that should not float a chat over it.
  static String setSection(
    Uri current,
    String path,
    PanelToken? section, {
    bool keepRoom = true,
  }) {
    final lists = parseOpenPanels(current);
    final left = <PanelToken>[
      ?section,
      if (keepRoom) ...lists.left.where((t) => t.type == 'room'),
    ];
    final parts = <String>[
      if (left.isNotEmpty) 'left=${left.map((t) => t.encode()).join(',')}',
      if (lists.right.isNotEmpty)
        'right=${lists.right.map((t) => t.encode()).join(',')}',
    ];
    return parts.isEmpty ? path : '$path?${parts.join('&')}';
  }

  /// Drop the whole `left` list (e.g. navigating to the world map, which has no
  /// left column). The `right` list and other query params are preserved.
  static String clearLeft(Uri current) =>
      _mutate(current, 'left', (_) => const []);

  /// Clear the entire workspace — every panel in both columns — and return to
  /// the world map (home). The World control is the one deliberate "reveal the
  /// full map" action; unlike a section navigation it carries nothing forward
  /// (see [preserveOpenPanels], which does not re-attach companions onto home).
  /// See `routing.instructions.md`.
  static String clearAll() => PRoutes.world;

  /// Add [token] to the `right` list (deduped). [atStart] places it to the left
  /// of the rest — a detail blooming left of its summary.
  static String openRight(Uri current, PanelToken token,
          {bool atStart = false}) =>
      _mutate(current, 'right', (tokens) => _add(tokens, token, atStart));

  static String closeLeft(Uri current, PanelToken token) =>
      _mutate(current, 'left', (tokens) => _remove(tokens, token));

  /// Close a *section* left panel (a course, the chat list, the add-course
  /// wizard). Returns to the world map path `/` and drops every non-panel query
  /// param — in particular a course's `?m=course:<id>` map filter — while
  /// keeping every *other* left panel and the whole right column. So closing a
  /// course exits its map filter and reveals the world without tearing down the
  /// rest ("move to the world"). A `room` is only ever a token, so it just drops
  /// its own token via [closeLeft]. See `routing.instructions.md`.
  static String closeSection(Uri current, PanelToken token) {
    final lists = parseOpenPanels(current);
    // A course's management page (`coursepage`) reads its space from the
    // `?m=course:<id>` filter this close clears, so left on its own it renders
    // blank with no close control — drop it together with the course card
    // (mirrors closeSettings dropping settingspage). See routing.instructions.md.
    final dropDependentCoursePage = token.type == 'course';
    final left = lists.left
        .where((t) =>
            t != token && !(dropDependentCoursePage && t.type == 'coursepage'))
        .toList();
    final parts = <String>[
      if (left.isNotEmpty) 'left=${left.map((t) => t.encode()).join(',')}',
      if (lists.right.isNotEmpty)
        'right=${lists.right.map((t) => t.encode()).join(',')}',
    ];
    return parts.isEmpty ? PRoutes.world : '${PRoutes.world}?${parts.join('&')}';
  }

  static String closeRight(Uri current, PanelToken token) =>
      _mutate(current, 'right', (tokens) => _remove(tokens, token));

  /// Replace the whole `right` list. Used when switching the analytics metric:
  /// the cluster drops the other analytics/detail tokens and seats one summary.
  static String setRight(Uri current, List<PanelToken> tokens) =>
      _mutate(current, 'right', (_) => tokens);

  /// Push a deeper page into a `pushable` panel's own token param (the panel's
  /// param IS its page path): settings menu→page→leaf, a course card→details/
  /// invite, a room→members/search. Replaces that panel's token with the
  /// deeper-page token, keeping every other panel. A null/empty [page] is the
  /// panel's root. See `routing.instructions.md`.
  static String pushPage(Uri current, String type, String? page) {
    final col =
        PanelRegistry.defFor(type)?.column == PanelColumn.right ? 'right' : 'left';
    return _mutate(current, col, (tokens) {
      final next = tokens.where((t) => t.type != type).toList();
      next.add(
        page == null || page.isEmpty ? PanelToken(type) : PanelToken(type, page),
      );
      return next;
    });
  }

  /// Pop one page level off a pushable panel (its back arrow): a `a/b` page
  /// returns to `a`; a top-level page returns to the panel's root.
  static String popPage(Uri current, String type, String page) {
    final parent =
        page.contains('/') ? page.substring(0, page.lastIndexOf('/')) : '';
    return pushPage(current, type, parent.isEmpty ? null : parent);
  }

  /// Open the settings/profile MENU as the right-column master (page null/empty),
  /// or a settings PAGE as its detail beside the menu. A page blooms at the front
  /// of the right group with the `settings` menu master kept (or seated) behind
  /// it — so they coexist when width allows and fold to a push when not. A
  /// `/`-path page is a leaf (its own back pops it). See `routing.instructions.md`.
  static String openSettings(Uri current, {String? page}) {
    if (page == null || page.isEmpty) {
      return _mutate(current, 'right', (tokens) {
        final next = tokens
            .where((t) => t.type != 'settings' && t.type != 'settingspage')
            .toList();
        next.add(const PanelToken('settings'));
        return next;
      });
    }
    final detail = PanelToken('settingspage', page);
    return _mutate(current, 'right', (tokens) {
      final next = tokens.where((t) => t.type != 'settingspage').toList();
      next.insert(0, detail);
      if (!next.any((t) => t.type == 'settings')) {
        next.add(const PanelToken('settings'));
      }
      return next;
    });
  }

  /// Close the whole settings/profile panel — the menu master AND its open page
  /// detail — keeping the rest of the right column. Closing the master drops its
  /// detail (it has no meaning without the menu).
  static String closeSettings(Uri current) => _mutate(
        current,
        'right',
        (tokens) => tokens
            .where((t) =>
                t.type != 'settings' &&
                t.type != 'profile' &&
                t.type != 'settingspage')
            .toList(),
      );

  /// The settings panel's back: a leaf (`a/b`) pops to its parent page; a
  /// top-level page returns to the menu (drops the page detail, menu remains).
  static String settingsBack(Uri current, String page) {
    if (page.contains('/')) {
      return openSettings(
          current, page: page.substring(0, page.lastIndexOf('/')));
    }
    return closeRight(current, PanelToken('settingspage', page));
  }

  static List<PanelToken> _add(
    List<PanelToken> tokens,
    PanelToken token,
    bool atStart,
  ) {
    final next = tokens.where((t) => t != token).toList();
    if (atStart) {
      next.insert(0, token);
    } else {
      next.add(token);
    }
    return next;
  }

  static List<PanelToken> _remove(List<PanelToken> tokens, PanelToken token) =>
      tokens.where((t) => t != token).toList();

  static String _mutate(
    Uri current,
    String key,
    List<PanelToken> Function(List<PanelToken>) transform,
  ) {
    final lists = parseOpenPanels(current);
    final next = transform(key == 'left' ? lists.left : lists.right);

    // Keep every other query param exactly as it appears (raw), and replace only
    // this key's segment with the freshly encoded token list.
    final parts = current.query.isEmpty ? <String>[] : current.query.split('&');
    parts.removeWhere((p) => p == key || p.startsWith('$key='));
    if (next.isNotEmpty) {
      parts.add('$key=${next.map((t) => t.encode()).join(',')}');
    }
    final query = parts.join('&');
    return query.isEmpty ? current.path : '${current.path}?$query';
  }

  /// Like [_mutate] but rewrites BOTH the `left` and `right` lists in one go,
  /// for cross-column moves (the shared detail slot: a left `session` and a
  /// right vocab/grammar detail are mutually exclusive). Every other query param
  /// (notably the `m` map filter) is preserved verbatim.
  static String _mutateBoth(
    Uri current,
    List<PanelToken> Function(List<PanelToken>) leftTransform,
    List<PanelToken> Function(List<PanelToken>) rightTransform,
  ) {
    final lists = parseOpenPanels(current);
    final left = leftTransform(lists.left);
    final right = rightTransform(lists.right);
    final parts = current.query.isEmpty ? <String>[] : current.query.split('&');
    parts.removeWhere(
      (p) =>
          p == 'left' ||
          p.startsWith('left=') ||
          p == 'right' ||
          p.startsWith('right='),
    );
    if (left.isNotEmpty) {
      parts.add('left=${left.map((t) => t.encode()).join(',')}');
    }
    if (right.isNotEmpty) {
      parts.add('right=${right.map((t) => t.encode()).join(',')}');
    }
    final query = parts.join('&');
    return query.isEmpty ? current.path : '${current.path}?$query';
  }
}
