import 'package:fluffychat/features/navigation/panel_token.dart';
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

  /// Open a live room panel, enforcing the one-live-session rule: any *other*
  /// `room` token in the left list is dropped first, because the Matrix room
  /// timeline is shared and two live views would overwrite each other (see
  /// `routing.instructions.md`). Other left surfaces — the chat list, a course
  /// (which scopes the room), settings — are kept and stay to the *left* of the
  /// room (the room is appended), so a list-then-chat master/detail reads left
  /// to right.
  static String openExclusiveLeftRoom(Uri current, PanelToken token) =>
      _mutate(current, 'left', (tokens) {
        final next = tokens.where((t) => t.type != 'room').toList();
        next.add(token);
        return next;
      });

  /// Open a vocab/grammar construct detail on the right, replacing any construct
  /// detail already open — one detail at a time, the right-column mirror of
  /// [openExclusiveLeftRoom]. The detail seats at the left edge of the right
  /// group (in front of its pinned `analytics` summary, which is kept), so the
  /// summary stays at the edge and its detail blooms to its left. See
  /// `routing.instructions.md`.
  static String openExclusiveRightDetail(Uri current, PanelToken token) =>
      _mutate(current, 'right', (tokens) {
        final next = tokens
            .where((t) => t.type != 'vocab' && t.type != 'grammar')
            .toList();
        next.insert(0, token);
        return next;
      });

  /// Open (or re-tab) a `course` panel at the left edge, replacing any existing
  /// course token. The course's identity is the path (`/courses/:spaceid`, read
  /// via activeSpaceIdFor) — not duplicated into the token; the token's param is
  /// just the active tab, so switching tabs is opening the course token with a
  /// new tab. A live room and the chat list are kept (a course can scope a room).
  static String openCourse(Uri current, PanelToken token) =>
      _mutate(current, 'left', (tokens) {
        final next = tokens.where((t) => t.type != 'course').toList();
        next.insert(0, token);
        return next;
      });

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

  /// Close a *section* left panel (a course, the chat list, settings). Unlike a
  /// `room` — which exists only as a token over some other path — a section is
  /// also addressable by its own path (`/courses/:id`, `/chats`, `/settings`),
  /// and the route-driven card (`SpaceNavigationColumn._MainView`) re-renders it
  /// from that path the instant the token is gone. So dropping the token is not
  /// enough: closing a section panel also returns to the world map path, while
  /// keeping every *other* left panel (a course-scoped live room) and the whole
  /// right column — so closing a course reveals the map without tearing down the
  /// rest ("move to the world"; see `routing.instructions.md`).
  static String closeSection(Uri current, PanelToken token) {
    final lists = parseOpenPanels(current);
    final left = lists.left.where((t) => t != token).toList();
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

  /// Open the profile + settings panel on the right at [page] (a sub-page id
  /// like `learning` or `security/password`; null/empty is the menu). The whole
  /// settings tree is one right-column panel whose param is the active page, so
  /// navigating to a sub-page is opening the `settings` token with a new param
  /// (a *push*) — the existing `settings` token is replaced, not stacked. Other
  /// right panels are kept. See `routing.instructions.md`.
  static String openSettings(Uri current, {String? page}) =>
      _mutate(current, 'right', (tokens) {
        final next = tokens.where((t) => t.type != 'settings').toList();
        next.add(
          page == null || page.isEmpty
              ? const PanelToken('settings')
              : PanelToken('settings', page),
        );
        return next;
      });

  /// Pop one level of settings depth (the panel's back arrow): a `security/x`
  /// sub-page returns to `security`, and any top-level sub-page returns to the
  /// menu. Closing the menu itself drops the token (see [closeRight]).
  static String settingsBack(Uri current, String page) {
    final parent =
        page.contains('/') ? page.substring(0, page.lastIndexOf('/')) : '';
    return openSettings(current, page: parent.isEmpty ? null : parent);
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
}
