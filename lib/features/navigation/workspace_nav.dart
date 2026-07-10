import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/navigation/token_params/grammar_analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/token_params/settings_token.dart';
import 'package:fluffychat/features/navigation/token_params/vocab_analytics_token.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

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
    final namesPanels = destination.query
        .split('&')
        .any(
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
  static String openLeft(
    Uri current,
    PanelToken token, {
    bool atStart = false,
  }) => _mutate(current, 'left', (tokens) => _add(tokens, token, atStart));

  /// Open (or replace) a DETAIL panel, enforcing the registry's **sibling**
  /// groups across BOTH columns: any open token that shares a sibling group with
  /// [token] is dropped (siblings can't coexist — one live view; one "zoom"
  /// detail across columns; see [PanelDef.siblingGroups]). The token seats in its
  /// own column — a right detail blooms at the front (left of its master); a left
  /// detail appends (after the list/course it details). This is the one
  /// generalized detail open; the named helpers below delegate to it. See
  /// `routing.instructions.md`.
  static String openDetail(Uri current, PanelToken token) {
    final col = token.type.def.column;
    return _mutateBoth(
      current,
      (left) => _placeDetail(left, token, PanelColumn.left, col),
      (right) => _placeDetail(right, token, PanelColumn.right, col),
    );
  }

  /// Drop siblings (and the token itself, for dedup) from one column's list,
  /// then append [token] when it belongs to [thisCol]. Canonical order is
  /// master-first in both columns (routing.instructions.md), so a detail
  /// appends after its master; edge-justification of the right column is the
  /// renderer's job, not the URL's. The other column just sheds siblings.
  static List<PanelToken> _placeDetail(
    List<PanelToken> tokens,
    PanelToken token,
    PanelColumn thisCol,
    PanelColumn tokenCol,
  ) {
    final next = tokens
        .where((t) => t != token && !_areSiblings(token, t))
        .toList();
    if (thisCol == tokenCol) next.add(token);
    return next;
  }

  /// True when [a] and [b] are **siblings** — they share any sibling group (per
  /// the registry), so they can't coexist and one replaces the other.
  static bool _areSiblings(PanelToken a, PanelToken b) {
    final ga = a.type.def.siblingGroups;
    final gb = b.type.def.siblingGroups;
    return ga.any(gb.contains);
  }

  /// A live room (chat) is a left detail in the `liveView` group, so opening one
  /// drops any other room/session and leaves the right column untouched.
  static String openExclusiveLeftRoom(Uri current, PanelToken token) =>
      openDetail(current, token);

  /// Open a live chat by ROOM ID from anywhere — the token-native replacement
  /// for every `context.go('/rooms/<id>')` path literal. [subPage] pushes a
  /// sub-page onto the room's own stack (`details`, `search`, …); [event] rides
  /// as the room token's `e/<eventId>` field (jump-to-message on the main
  /// timeline) instead of a loose `?event=` query — everything the panel needs
  /// rides in its token (routing.instructions.md).
  static String openRoomById(
    Uri current,
    String roomId, {
    String? subPage,
    String? event,
  }) {
    final id = shortRoomId(roomId);
    final param = RoomTokenParam(id: id, subpage: subPage, eventId: event);
    return WorkspaceQuery.location(
      PRoutes.world,
      WorkspaceQuery.parts(
        Uri.parse(openExclusiveLeftRoom(current, RoomPanelToken(param))).query,
      ),
    );
  }

  /// A completed-activity `session` review (opened from the Stars archive) is a
  /// left detail in BOTH `liveView` and `detail`, so opening it drops any other
  /// room/session AND any vocab/grammar detail (one detail across columns). It
  /// ALSO drops the open `course` card and its `coursepage` so the review isn't
  /// rendered behind a still-open course window (#7106) — the Stars archive is
  /// this helper's only caller, and a live in-course session opens via
  /// [openExclusiveLeftRoom] (+ [openCourse]) instead, so the course is
  /// only dropped on the Stars path. (Not a shared sibling group: that would
  /// evict the course on every room/vocab/grammar/practice open too.)
  static String openExclusiveSession(Uri current, String roomId) {
    final token = SessionPanelToken(RoomTokenParam(id: shortRoomId(roomId)));

    return _mutateBoth(current, (left) {
      final next = left
          .where(
            (t) =>
                t != token &&
                !_areSiblings(token, t) &&
                t.type != PanelTypesEnum.course &&
                t.type != PanelTypesEnum.coursepage,
          )
          .toList();
      next.add(token);
      return next;
    }, (right) => right.where((t) => !_areSiblings(token, t)).toList());
  }

  /// Open a vocab/grammar construct detail (the `detail` group): drops the
  /// other construct detail and any `session`, ensures its pinned `analytics`
  /// summary master exists (seated at [summaryTab] from a cold start), and
  /// appends the detail after it — master-first canonical order, with the
  /// renderer blooming the detail to the left of the edge-justified master. See
  /// `routing.instructions.md`.
  static String openConstructDetail(
    Uri current,
    ConstructTypeEnum view, {
    ConstructIdentifier? constructId,
  }) {
    final PanelToken detail = view == ConstructTypeEnum.vocab
        ? VocabAnalyticsPanelToken(
            VocabAnalyticsTokenParam(constructId: constructId),
          )
        : GrammarAnalyticsPanelToken(
            GrammarAnalyticsTokenParam(constructId: constructId),
          );

    return _mutateBoth(
      current,
      (left) => left.where((t) => !_areSiblings(detail, t)).toList(),
      (right) {
        final next = right
            .where((t) => t != detail && !_areSiblings(detail, t))
            .toList();

        if (!next.any((t) => t.type == PanelTypesEnum.analytics)) {
          next.insert(
            0,
            AnalyticsPanelToken(AnalyticsTokenParam(subpage: view.indicator)),
          );
        }

        next.add(detail);
        return next;
      },
    );
  }

  /// Open a practice session as a right-column panel that **takes over the
  /// analytics surface**: it clears the analytics master and any vocab/grammar
  /// detail on the right (and a left `session` review — practice shares the one
  /// "detail" slot across columns), then seats `practice:<type>` at the front.
  /// While practice is open no vocab/grammar list or detail can be viewed —
  /// opening one drops practice (the registry `detail` group), and tapping the
  /// cluster's analytics replaces the whole right column. Practice is a normal
  /// bounded panel, not a route or a fullscreen surface. See
  /// `routing.instructions.md`.
  static String openPractice(Uri current, ConstructTypeEnum type) =>
      _mutateBoth(
        current,
        (left) => left.where((t) => t.type != PanelTypesEnum.session).toList(),
        (right) {
          final next = right.where((t) => !t.type.isAnalyticsPanel).toList();
          next.insert(
            0,
            AnalyticsPracticePanelToken(
              AnalyticsPracticeTokenParam(constructType: type),
            ),
          );
          return next;
        },
      );

  /// Switch the workspace to course [spaceId]: set the `?c=<id>` scope
  /// filter AND a `course` left panel (at [tab] in its param if given),
  /// replacing any prior course filter/token. Keeps the chat list, the right
  /// column, and every other query. This is the token-native "open this course
  /// from anywhere" used when navigating to a course outside its current filter
  /// (joins, activity-session returns) — the tab must ride the token param, so a
  /// bare `?tab=` query cannot express it. See `routing.instructions.md`.
  static String openCourse(
    Uri current,
    String spaceId, {
    SpaceSettingsTabs? tab,
  }) {
    final lists = parseOpenPanels(current);
    final left = <PanelToken>[
      CoursePanelToken(
        tab != null ? CourseDetailsTokenParam(activeTab: tab) : null,
      ),
      // Drop any prior course token, the Courses launcher (`addcourse`), a stale
      // management page (`coursepage`), and an open immersive `activity` —
      // picking/re-showing a course card is an exit FROM the activity (the
      // in-course "Pick different activity" / "Return to course" buttons route
      // here), so the live-view activity must not co-render beside the card
      // (#7385). A live `room` is kept (a course can scope a chat).
      ...lists.left.where((t) => !t.type.isCoursePanel),
    ];
    final parts = WorkspaceQuery.parts(current.query);
    WorkspaceQuery.removeKeys(parts, {'c', 'left'});
    final query = <String>[
      'c=${Uri.encodeComponent(shortRoomId(spaceId))}',
      'left=${left.map((t) => t.encode()).join(',')}',
      ...parts,
    ];
    return WorkspaceQuery.location(PRoutes.world, query);
  }

  /// Switch the LEFT SECTION to course [spaceId] — a rail / bottom-nav section
  /// tap. Sets the `?c=` context and REPLACES the open left panels with the
  /// course card ([tab] in its param), keeping a live room only when
  /// [keepRoom]; the right column and other query survive. Unlike
  /// [openCourse] (an in-content course open, which keeps the chat
  /// list), a section switch replaces the left column
  /// (routing.instructions.md). This is the token-native replacement for the
  /// old `setSection(uri, PRoutes.course(id), …)` hybrid that bounced through
  /// the legacy redirect.
  static String openCourseSection(
    Uri current,
    String spaceId, {
    bool keepRoom = true,
    bool clearRight = false,
  }) {
    final lists = parseOpenPanels(current);
    final left = <PanelToken>[
      CoursePanelToken(),
      if (keepRoom) ...lists.left.where((t) => t.type == PanelTypesEnum.room),
    ];
    final parts = WorkspaceQuery.parts(current.query);
    WorkspaceQuery.removeKeys(parts, {
      'c',
      'left',
      // Single-column: a rail section closes an open right panel (peers in
      // the same slot — see setSection's clearRight).
      if (clearRight) 'right',
    });
    final query = <String>[
      'c=${Uri.encodeComponent(shortRoomId(spaceId))}',
      'left=${left.map((t) => t.encode()).join(',')}',
      ...parts,
    ];
    return WorkspaceQuery.location(PRoutes.world, query);
  }

  /// Open a tab in the detail page for the currently focused course
  static String openCourseTab(Uri current, {SpaceSettingsTabs? tab}) => _mutate(
    current,
    'left',
    (tokens) {
      // Drop any prior course token AND an open immersive `activity` — showing
      // the course card is an exit from the activity, so the live-view activity
      // must not co-render beside it (#7385). A live `room` is kept.
      final next = tokens
          .where(
            (t) =>
                t.type != PanelTypesEnum.course &&
                t.type != PanelTypesEnum.activity,
          )
          .toList();
      next.insert(0, CoursePanelToken(CourseDetailsTokenParam(activeTab: tab)));
      return next;
    },
  );

  /// Open a course-management page (invite / edit / access / permissions /
  /// emotes / change-course) as the course card's DETAIL — a `coursepage` panel
  /// beside the `course` master that coexists when width allows and folds to a
  /// push when not, mirroring settings menu→page ([openSettings]). The card's
  /// space rides in the `?c=<id>` scope (preserved here), so the page
  /// param is just the page id, with an optional trailing `/<filter>` — the
  /// invite page's initial contact filter, folded into the token instead of a
  /// loose `?filter=` query (routing.instructions.md). One management page at a
  /// time (the registry `coursepage` exclusive group drops any prior one).
  static String openCoursePage(
    Uri current,
    RoomSubpageEnum? page, {
    InvitationFilter? filter,
    String? courseId,
  }) {
    return openDetail(
      current,
      CoursePagePanelToken(
        RoomSubpageTokenParam(
          subpage: page,
          inviteFilter: filter,
          courseId: courseId,
        ),
      ),
    );
  }

  /// Open course [spaceId]'s management [page] (invite / edit / …) from
  /// ANYWHERE: set the `?c=<id>` scope + `course` card, then the
  /// `coursepage:<page>` detail beside it. Same shape as [openCoursePage] on the
  /// already-scoped course — use this when the target course may not be the
  /// current filter (e.g. inviting knocking users from a space tile, or from an
  /// activity session). See `routing.instructions.md`.
  static String openCoursePageFor(
    Uri current,
    String spaceId,
    RoomSubpageEnum page, {
    InvitationFilter? filter,
  }) => openCoursePage(
    Uri.parse(openCourse(current, spaceId)),
    page,
    filter: filter,
  );

  /// Open an in-course activity as the immersive `left=activity:` panel over
  /// the course-scoped map — the token-native producer for "open this activity
  /// in its course". Sets the `?c=<spaceId>` course context and seats the
  /// activity as the SOLE left token (no chat list / room / course card beside
  /// it): an activity is an immersive task that claims the single live view —
  /// its registry `liveView` sibling group drops any open `room`/`session`, and
  /// starting the session (which opens a `room` token) drops the activity in
  /// turn. The surviving context keeps the plan's close a back-arrow that
  /// reopens the card. [launch] skips the lobby straight to role selection;
  /// [roomId] reopens/rejoins a specific session room; [autoplay] autostarts
  /// the plan's hero media (muted, block 0) — all three ride as fields of the
  /// activity token's param ([ActivityTokenParam]), never as loose query params.
  ///
  /// Inbound `/courses/:id?activity=` external links and the standalone
  /// `/<uuid>` link map to this same token form through `legacy_redirects`. The
  /// clean-left seating also fixes #7267 (the legacy path producer re-opened
  /// `left=course` beside the activity). See `routing.instructions.md`.
  static String openCourseActivity(
    String spaceId,
    String activityId, {
    bool launch = false,
    String? roomId,
    bool autoplay = false,
  }) {
    final token = ActivityPanelToken(
      ActivityTokenParam(
        activityId: activityId,
        roomId: roomId,
        launch: launch,
        autoplay: autoplay ? 0 : null,
      ),
    );

    final parts = <String>[
      'c=${Uri.encodeComponent(shortRoomId(spaceId))}',
      'left=${token.encode()}',
    ];

    return WorkspaceQuery.location(PRoutes.world, parts);
  }

  /// Seat [activityId] as the SOLE left `activity:` token over the current
  /// map — the token-native "open this activity from here" (a map pin tap, a
  /// start-page reopen). Session binding, launch, and autoplay ride the
  /// token's fields. **The course context is never consumed**
  /// (routing.instructions.md): a pin on a course-scoped map keeps `?c=` (so
  /// the plan closes with a back-arrow to the course), a pin on the world map
  /// has none (so it closes with an X). The right column is left untouched —
  /// an activity is a left-column live view, independent of an open analytics
  /// panel.
  static String openActivity(
    Uri current,
    String activityId, {
    String? roomId,
    bool launch = false,
    int? autoplay,
  }) {
    final parts = WorkspaceQuery.parts(current.query);
    WorkspaceQuery.removeKeys(parts, {'left'});

    final token = ActivityPanelToken(
      ActivityTokenParam(
        activityId: activityId,
        roomId: roomId,
        launch: launch,
        autoplay: autoplay,
      ),
    );

    parts.add('left=${token.encode()}');
    return WorkspaceQuery.location(PRoutes.world, parts);
  }

  /// Drop the open `activity` token, keeping the rest of the workspace —
  /// notably the course context, which a close never consumes
  /// (routing.instructions.md). [reopenCourseCard] additionally reseats the
  /// `course` card over a surviving context (the plan's back-arrow target).
  /// Emits the world path: activity overlays only ever ride over the map.
  static String dropActivityOverlay(
    Uri current, {
    bool reopenCourseCard = false,
  }) {
    final parts = WorkspaceQuery.parts(current.query);
    WorkspaceQuery.removeKeys(parts, {'left'});
    final left = parseOpenPanels(
      current,
    ).left.where((t) => t.type != PanelTypesEnum.activity).toList();
    if (reopenCourseCard &&
        activeSpaceIdFor(current) != null &&
        left.every((t) => t.type != PanelTypesEnum.course)) {
      left.insert(0, const CoursePanelToken());
    }
    if (left.isNotEmpty) {
      parts.add('left=${left.map((t) => t.encode()).join(',')}');
    }
    return WorkspaceQuery.location(PRoutes.world, parts);
  }

  /// Replace the whole `left` list (e.g. tapping a top-level section: Chats,
  /// the avatar/profile). The `right` list and other query params are preserved.
  static String setLeft(Uri current, List<PanelToken> tokens) =>
      _mutate(current, 'left', (_) => tokens);

  /// Navigate to a section — Chats, Courses/the add-course hub, or the world
  /// map — setting [section] as the sole section panel while **keeping the
  /// live room and the right column** — so navigating between sections changes
  /// which panel is focused instead of tearing the open chat down ("move to the
  /// world and keep the chat"; see `routing.instructions.md`). Pass `null` for
  /// the world map (no section panel). The section sits to the left of the room
  /// so a list/detail reads left-to-right. Set [keepRoom] false for a focused
  /// full-bleed flow (the add-course hub) that should not float a chat over it.
  /// Always emits the world path `/` — section identity rides entirely in the
  /// token, never a path segment (a joined course is `openCourseSection`, which
  /// also sets the `?c=` context this helper does not touch).
  /// [clearRight] (single-column callers): drop the right list too — on one
  /// column a rail section and a right panel are peers in the same slot, so
  /// navigating to a section closes an open analytics/settings panel instead
  /// of leaving it stale behind the sheet (the mirror of [setRight]'s
  /// `closeSections`).
  static String setSection(
    Uri current,
    PanelToken? section, {
    bool keepRoom = true,
    bool clearRight = false,
  }) {
    final lists = parseOpenPanels(current);
    final left = <PanelToken>[
      ?section,
      if (keepRoom) ...lists.left.where((t) => t.type == PanelTypesEnum.room),
    ];
    // Carry the course context forward: context (`?c=`) is independent of
    // panels and changes only when a new course is chosen or the World control
    // resets it — never by switching sections (see routing.instructions.md).
    final parts = <String>[
      ?_courseContext(current),
      if (left.isNotEmpty) 'left=${left.map((t) => t.encode()).join(',')}',
      if (!clearRight && lists.right.isNotEmpty)
        'right=${lists.right.map((t) => t.encode()).join(',')}',
    ];
    return WorkspaceQuery.location(PRoutes.world, parts);
  }

  /// The raw `c=<spaceid>` course-context segment of [current]'s query, or
  /// null. Context is scope state, independent of which panels are open, so
  /// the section/close helpers carry it forward verbatim. See
  /// `routing.instructions.md`.
  static String? _courseContext(Uri current) {
    for (final p in current.query.split('&')) {
      if (p.startsWith('c=')) return p;
    }
    return null;
  }

  /// Clear the entire workspace — every panel in both columns — and return to
  /// the world map (home). The World control is the one deliberate "reveal the
  /// full map" action; unlike a section navigation it carries nothing forward
  /// (see [preserveOpenPanels], which does not re-attach companions onto home).
  /// See `routing.instructions.md`.
  static String clearAll() => PRoutes.world;

  /// Add [token] to the `right` list (deduped). [atStart] places it to the left
  /// of the rest — a detail blooming left of its summary.
  static String openRight(
    Uri current,
    PanelToken token, {
    bool atStart = false,
  }) => _mutate(current, 'right', (tokens) => _add(tokens, token, atStart));

  static String closeLeft(Uri current, PanelToken token) =>
      _mutate(current, 'left', (tokens) => _remove(tokens, token));

  /// Close a *section* left panel (a course, the chat list, the add-course
  /// wizard), dropping its token while **keeping the map filter** and the rest of
  /// the workspace. Closing a course card therefore leaves `?c=<id>` in
  /// place — the map stays course-scoped (its pins visible) with the card gone;
  /// scope is reset only by the World control or by choosing a different course,
  /// never by closing a panel (see `routing.instructions.md`). A `room` is only
  /// ever a token, so it just drops its own token via [closeLeft].
  static String closeSection(Uri current, PanelToken token) {
    final lists = parseOpenPanels(current);
    // Drop only this token, nothing else — "closing a panel drops its token and
    // nothing else" (routing.instructions.md). A course card's management page
    // (`coursepage`) therefore stays open when the card closes, exactly as the
    // chat list's `room` child stays when the list closes; both read on from the
    // surviving `?c=` scope / their own id. (A coursepage left with no
    // course scoped at all is shed by route_facts, not here.)
    final left = lists.left.where((t) => t != token).toList();
    // Preserve unrelated one-shot query the way closeLeft/_mutate already do —
    // recompute only c/left/right and carry the rest forward. Critically this
    // keeps `?activity=`/`?launch=`/`?roomid=` (a launching or running activity
    // renders as the center canvas, independent of the course card), so closing
    // the course no longer unmounts/aborts the activity (#7111). The scope
    // (`?c=`) is re-added below, so drop it from the carried set to avoid a dupe.
    final rest = WorkspaceQuery.parts(current.query);
    WorkspaceQuery.removeKeys(rest, {'c', 'left', 'right'});
    final parts = <String>[
      ?_courseContext(current),
      if (left.isNotEmpty) 'left=${left.map((t) => t.encode()).join(',')}',
      if (lists.right.isNotEmpty)
        'right=${lists.right.map((t) => t.encode()).join(',')}',
      ...rest,
    ];
    return WorkspaceQuery.location(PRoutes.world, parts);
  }

  static String closeRight(Uri current, PanelToken token) =>
      _mutate(current, 'right', (tokens) => _remove(tokens, token));

  /// Replace the whole `right` list. Used when switching the analytics metric:
  /// the cluster drops the other analytics/detail tokens and seats one summary.
  ///
  /// [closeSections] (single-column callers): also drop the left SECTION
  /// tokens — on one column the right panel takes the section's slot, so
  /// closing the panel must reveal the map, not a stale sheet. A live
  /// `room`/`session` is kept (see [_leftSections]).
  static String setRight(
    Uri current,
    List<PanelToken> tokens, {
    bool closeSections = false,
  }) {
    final next = _mutate(current, 'right', (_) => tokens);
    if (!closeSections) return next;
    return _mutate(
      Uri.parse(next),
      'left',
      (left) => left.where((t) => !t.type.isLeftSection).toList(),
    );
  }

  /// Push a deeper page into a `pushable` panel's own token param (the panel's
  /// param IS its page path): settings menu→page→leaf, a course card→details/
  /// invite, a room→members/search. Replaces that panel's token with the
  /// deeper-page token, keeping every other panel. A null/empty [page] is the
  /// panel's root. See `routing.instructions.md`.
  static String pushPage(Uri current, PanelToken token) {
    final col = token.type.def.column == PanelColumn.right ? 'right' : 'left';
    return _mutate(current, col, (tokens) {
      final next = tokens.where((t) => t.type != token.type).toList();
      next.add(token);
      return next;
    });
  }

  /// Pop one page level off a pushable panel (its back arrow): a `a/b` page
  /// returns to `a`; a top-level page returns to the panel's root.
  static String popPage(Uri current, PanelToken token) {
    final popped = token.popped;
    if (popped != null) {
      return pushPage(current, popped);
    }

    final col = token.type.def.column == PanelColumn.right ? 'right' : 'left';
    return _mutate(current, col, (tokens) => _remove(tokens, token));
  }

  /// Open the settings/profile MENU as the right-column master (page null/empty),
  /// or a settings PAGE as its detail beside the menu. The `settings` menu master
  /// is kept (or seated) first and the page appended after it — master-first
  /// canonical order — so they coexist when width allows (the renderer blooms
  /// the page left of the edge menu) and fold to a push when not. A `/`-path
  /// page is a leaf (its own back pops it). Opening Settings also drops any open
  /// analytics-family panel so the two don't clutter the right column together
  /// (#7109). See `routing.instructions.md`.
  /// [closeSections] mirrors [setRight]'s flag for single-column callers.
  static String openSettings(
    Uri current, {
    String? page,
    bool closeSections = false,
  }) {
    final String next;
    if (page == null || page.isEmpty) {
      next = _mutate(current, 'right', (tokens) {
        final result = tokens
            .where(
              (t) =>
                  t.type != PanelTypesEnum.settings &&
                  t.type != PanelTypesEnum.settingspage &&
                  !t.type.isAnalyticsPanel,
            )
            .toList();
        result.add(const SettingsPanelToken());
        return result;
      });
    } else {
      final detail = SettingsPagePanelToken(SettingsTokenParam(subpage: page));
      next = _mutate(current, 'right', (tokens) {
        final result = tokens
            .where(
              (t) =>
                  t.type != PanelTypesEnum.settingspage &&
                  !t.type.isAnalyticsPanel,
            )
            .toList();
        if (!result.any((t) => t.type == PanelTypesEnum.settings)) {
          result.insert(0, const SettingsPanelToken());
        }
        result.add(detail);
        return result;
      });
    }
    if (!closeSections) return next;
    return _mutate(
      Uri.parse(next),
      'left',
      (left) => left.where((t) => !t.type.isLeftSection).toList(),
    );
  }

  /// Close the settings/profile MENU master, dropping only the `settings`
  /// token — "closing a panel drops its token and nothing else"
  /// (routing.instructions.md), the same rule [closeSection] documents for the
  /// course family. An open `settingspage` detail therefore survives a menu
  /// close exactly as a `coursepage` survives its `course` card closing: the
  /// page keeps rendering (it reads its own identity from its token param, not
  /// from the menu), just without its master beside it. The page's own close
  /// still drops it via [closeRight]/[settingsBack] (#7493).
  static String closeSettings(Uri current) => _mutate(
    current,
    'right',
    (tokens) => _remove(tokens, const SettingsPanelToken()),
  );

  /// The settings panel's back: a leaf (`a/b`) pops to its parent page; a
  /// top-level page returns to the menu (drops the page detail, menu remains).
  static String settingsBack(Uri current, String page) {
    final param = SettingsTokenParam(subpage: page);
    if (param.isPushed) {
      final popped = param.poppedParam;
      if (popped is SettingsTokenParam) {
        return openSettings(current, page: popped.subpage);
      }
    }
    return closeRight(current, SettingsPagePanelToken(param));
  }

  static String openAddCourse(Uri current) =>
      setSection(current, AddCoursePanelToken());

  static String openAddCoursePage(
    Uri current,
    AddCourseSubpageEnum page, {
    String? initialLanguageFilter,
    String? previewRoomId,
    String? createCourseId,
    bool showNewCourseInvitePage = false,
    String? privateCourseJoinCode,
  }) => _mutate(
    current,
    'left',
    (_) => [
      AddCoursePanelToken(),
      AddCoursePagePanelToken(
        AddCoursePageTokenParam(
          subpage: page,
          initialLanguageFilter: initialLanguageFilter,
          previewRoomId: previewRoomId,
          createCourseId: createCourseId,
          showNewCourseInvitePage: showNewCourseInvitePage,
          privateCourseJoinCode: privateCourseJoinCode,
        ),
      ),
    ],
  );

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
    final parts = WorkspaceQuery.parts(current.query);
    WorkspaceQuery.removeKeys(parts, {key});
    if (next.isNotEmpty) {
      parts.add('$key=${next.map((t) => t.encode()).join(',')}');
    }
    return WorkspaceQuery.location(current.path, parts);
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
    final parts = WorkspaceQuery.parts(current.query);
    WorkspaceQuery.removeKeys(parts, {'left', 'right'});
    if (left.isNotEmpty) {
      parts.add('left=${left.map((t) => t.encode()).join(',')}');
    }
    if (right.isNotEmpty) {
      parts.add('right=${right.map((t) => t.encode()).join(',')}');
    }
    return WorkspaceQuery.location(current.path, parts);
  }

  static String openAnalytics(
    Uri current, {
    ProgressIndicatorEnum? subpage,
    bool closeSections = false,
  }) => setRight(current, [
    AnalyticsPanelToken(
      AnalyticsTokenParam(subpage: subpage ?? ProgressIndicatorEnum.wordsUsed),
    ),
  ], closeSections: closeSections);

  static String closeConstructDetail(Uri current, ConstructTypeEnum view) =>
      setRight(current, [
        AnalyticsPanelToken(
          AnalyticsTokenParam.parse(
            view == ConstructTypeEnum.vocab ? 'vocab' : 'grammar',
          ),
        ),
      ]);

  static String closeCoursePage(Uri current, RoomSubpageEnum page) => _mutate(
    current,
    'left',
    (tokens) => tokens.where((t) {
      if (t.type != PanelTypesEnum.coursepage) return true;
      final param = t.param;
      if (param is! RoomSubpageTokenParam) return true;
      return param.subpage != page;
    }).toList(),
  );
}
