import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/widgets/layouts/panel_allocator.dart';
import 'package:fluffychat/widgets/layouts/workspace_shell.dart';

/// Regression coverage for #7104 ("open tabs switching places"): with two popups
/// open in two columns, navigating WITHIN one popup (Settings → Subscription)
/// must NOT make the OTHER popup change columns / disappear.
///
/// Cause: the narrow/collapse focus signal (`focusHint`) was keyed on the
/// per-page token string, so a within-panel navigation minted a "new" token id
/// that the recency sync promoted to the back-stack top, stealing focus from the
/// unrelated popup; the column-mode Tier-2 parity collapse then evicted that other
/// popup. The fix keys recency on STABLE panel identity (the navigation-tree
/// family root) and resolves a shared key to the leaf pane.
///
/// Drives the REAL production focus rule ([recencyFocusHint] in
/// `workspace_shell.dart`) over real nav-helper URLs → parser → allocator, so
/// there is no mirrored logic to drift out of lock-step.
void main() {
  // The production back-stack the shell mutates per build; reset per test.
  final paneRecency = <String>[];
  int? focusHintFor(List<PanelToken> all) => recencyFocusHint(all, paneRecency);

  WorkspaceLayout layoutOf(Uri u, double vp, {required bool columnMode}) {
    final lists = parseOpenPanels(u);
    final fh = focusHintFor([...lists.left, ...lists.right]);
    return PanelAllocator.allocate(
      viewport: vp,
      isColumnMode: columnMode,
      railWidth: columnMode ? 105.0 : PanelAllocator.defaultRailWidth,
      left: [for (final t in lists.left) t.type.def],
      right: [for (final t in lists.right) t.type.def],
      focusHint: fh,
    );
  }

  PanelVis visOf(WorkspaceLayout l, Uri u, PanelTypesEnum type) {
    final lists = parseOpenPanels(u);
    final li = lists.left.indexWhere((t) => t.type == type);
    if (li >= 0) return l.left[li].vis;
    final ri = lists.right.indexWhere((t) => t.type == type);
    if (ri >= 0) return l.right[ri].vis;
    return PanelVis.hidden;
  }

  double? leftOf(WorkspaceLayout l, Uri u, PanelTypesEnum type) {
    final lists = parseOpenPanels(u);
    final li = lists.left.indexWhere((t) => t.type == type);
    if (li >= 0) return l.left[li].left;
    final ri = lists.right.indexWhere((t) => t.type == type);
    if (ri >= 0) return l.right[ri].left;
    return null;
  }

  setUp(paneRecency.clear);

  // The type of the pane the recency rule currently focuses, replaying each
  // build in order (recency accumulates per build, like the live shell).
  PanelTypesEnum focusType(Uri u) {
    final all = [...parseOpenPanels(u).left, ...parseOpenPanels(u).right];
    return all[focusHintFor(all)!].type;
  }

  group('#7104 — navigating within a popup keeps the other popup put', () {
    test('a push inside a NON-focused popup does not steal focus from the '
        'most-recent popup (the core regression)', () {
      // Open a room (left), THEN an analytics summary (right): analytics is the
      // most-recently opened, so it holds focus. A push WITHIN the room
      // (room → members) must NOT steal focus to the room. Before the fix the
      // per-page token id changed, promoting the room to the back-stack top, and
      // the tight-band Tier-2 collapse then evicted the analytics popup — the
      // visible "swap". This case fails on the pre-fix (token-string) keying and
      // passes on the stable-identity keying.
      var u = Uri.parse(
        WorkspaceNav.openLeft(
          Uri.parse('/'),
          PanelToken(PanelTypesEnum.room, RoomTokenParam.parse('!abc')),
        ),
      );
      expect(focusType(u), PanelTypesEnum.room);
      u = Uri.parse(
        WorkspaceNav.setRight(u, [
          PanelToken(
            PanelTypesEnum.analytics,
            AnalyticsTokenParam.parse('vocab'),
          ),
        ]),
      );
      expect(focusType(u), PanelTypesEnum.analytics);
      u = Uri.parse(
        WorkspaceNav.pushPage(
          u,
          PanelTypesEnum.room,
          RoomTokenParam.parse('!abc/members'),
        ),
      );
      expect(
        focusType(u),
        PanelTypesEnum.analytics,
        reason:
            'a push inside the non-focused room must not steal focus (#7104)',
      );
    });

    test('tight band: navigating the non-focused popup does not evict the focused '
        'popup (the visible symptom)', () {
      // The Tier-2 parity-collapse band (#7088): with two opposite-column
      // popups whose hard-mins overflow, only the focused one stays full. Open
      // settings, THEN a course — the course is most-recent, so it holds focus
      // and (protected from the collapse) stays full while settings yields.
      const vp = 900.0;
      var u = Uri.parse(WorkspaceNav.openSettings(Uri.parse('/')));
      layoutOf(u, vp, columnMode: true); // build 1: settings (right)
      u = Uri.parse(WorkspaceNav.openCourse(u, '!space:server'));
      final before = layoutOf(u, vp, columnMode: true); // build 2: course focus
      expect(
        visOf(before, u, PanelTypesEnum.course),
        PanelVis.full,
        reason: 'the most-recent (course) popup holds focus and stays full',
      );
      // Guard that we are genuinely in the collapse band (else the assertion
      // below is trivially true): the non-focused settings popup is the one
      // that yields. course (priority 60) > settingspage (55), so course can
      // ONLY be evicted by focus protecting the other popup — exactly the
      // pre-fix focus-steal this test pins.
      expect(
        visOf(before, u, PanelTypesEnum.settings),
        PanelVis.hidden,
        reason: 'the band must force a collapse for this test to discriminate',
      );

      // Navigate WITHIN settings (the NON-focused popup) → subscription. Before
      // the fix this stole focus to settings and the collapse evicted course
      // (course flipped full→hidden — the "swap"). The focused popup must stay.
      u = Uri.parse(WorkspaceNav.openSettings(u, page: 'subscription'));
      final after = layoutOf(u, vp, columnMode: true);
      expect(
        visOf(after, u, PanelTypesEnum.course),
        PanelVis.full,
        reason:
            'a nav inside the other popup must not evict the focused course (#7104)',
      );
      expect(visOf(after, u, PanelTypesEnum.settingspage), PanelVis.hidden);
    });

    test('wide column mode: left room stays at the same x across the nav', () {
      const vp = 1600.0;
      var u = Uri.parse(
        WorkspaceNav.openLeft(
          Uri.parse('/'),
          const PanelToken(PanelTypesEnum.room, RoomTokenParam(id: '!abc')),
        ),
      );
      u = Uri.parse(WorkspaceNav.openSettings(u)); // open settings (right)
      final before = layoutOf(u, vp, columnMode: true);
      final roomXBefore = leftOf(before, u, PanelTypesEnum.room);
      expect(visOf(before, u, PanelTypesEnum.room), PanelVis.full);

      // Navigate WITHIN settings → subscription (the other popup must not move).
      u = Uri.parse(WorkspaceNav.openSettings(u, page: 'subscription'));
      final after = layoutOf(u, vp, columnMode: true);
      expect(
        visOf(after, u, PanelTypesEnum.room),
        PanelVis.full,
        reason: 'room must stay',
      );
      expect(
        leftOf(after, u, PanelTypesEnum.room),
        roomXBefore,
        reason: 'room must not shift columns/position (#7104)',
      );
      expect(visOf(after, u, PanelTypesEnum.settingspage), PanelVis.full);
    });

    test(
      'within-panel navigation keeps focus in the settings family, never the '
      'other popup',
      () {
        // The real #7104 invariant, stated order-independently: navigating
        // the settings panel (menu → page → page) never steals focus to the
        // open room popup. (The menu→page step legitimately moves focus to
        // the page; page→page is stable.)
        var u = Uri.parse(
          WorkspaceNav.openLeft(
            Uri.parse('/'),
            const PanelToken(PanelTypesEnum.room, RoomTokenParam(id: '!abc')),
          ),
        );
        u = Uri.parse(WorkspaceNav.openSettings(u));
        expect(focusType(u), PanelTypesEnum.settings); // the menu, not the room
        u = Uri.parse(WorkspaceNav.openSettings(u, page: 'subscription'));
        expect(
          focusType(u),
          PanelTypesEnum.settingspage,
        ); // the page, still settings family
        u = Uri.parse(WorkspaceNav.openSettings(u, page: 'learning'));
        expect(
          focusType(u),
          PanelTypesEnum.settingspage,
        ); // stable, never the room
      },
    );

    test('within-panel navigation never changes focusHint (room push)', () {
      int? fhOf(Uri u) {
        final ls = parseOpenPanels(u);
        return focusHintFor([...ls.left, ...ls.right]);
      }

      var u = Uri.parse(WorkspaceNav.openSettings(Uri.parse('/')));
      u = Uri.parse(
        WorkspaceNav.openLeft(
          u,
          const PanelToken(PanelTypesEnum.room, RoomTokenParam(id: '!abc')),
        ),
      );
      final fhRoom = fhOf(u);
      u = Uri.parse(
        WorkspaceNav.pushPage(
          u,
          PanelTypesEnum.room,
          RoomTokenParam(id: '!abc/members'),
        ),
      );
      final fhMembers = fhOf(u);
      expect(fhMembers, fhRoom);
    });
  });

  group('#7104 fix must not regress narrow-mode detail-show', () {
    test('opening a settings page shows the page over the menu (narrow)', () {
      var u = Uri.parse(WorkspaceNav.openSettings(Uri.parse('/')));
      u = Uri.parse(WorkspaceNav.openSettings(u, page: 'subscription'));
      final l = layoutOf(u, 400, columnMode: false);
      expect(visOf(l, u, PanelTypesEnum.settingspage), PanelVis.full);
      expect(visOf(l, u, PanelTypesEnum.settings), PanelVis.hidden);
    });

    test('opening a construct detail shows it over the summary (narrow)', () {
      var u = Uri.parse(
        WorkspaceNav.setRight(Uri.parse('/'), [
          PanelToken(
            PanelTypesEnum.analytics,
            AnalyticsTokenParam.parse('vocab'),
          ),
        ]),
      );

      final type = ConstructTypeEnum.vocab;
      final constructId = ConstructIdentifier.fromTokenParam(type, 'hablar');

      u = Uri.parse(
        WorkspaceNav.openConstructDetail(u, type, constructId: constructId),
      );
      final l = layoutOf(u, 400, columnMode: false);
      expect(visOf(l, u, PanelTypesEnum.vocab), PanelVis.full);
      expect(visOf(l, u, PanelTypesEnum.analytics), PanelVis.hidden);
    });

    test(
      'opening a course page shows the page over the card (narrow, left detail '
      'appended after master — leaf resolution)',
      () {
        // A course needs its `?m=course:<id>` filter for the parser to keep the
        // `course`/`coursepage` tokens (the card's identity rides the filter).
        var u = Uri.parse(
          WorkspaceNav.openCourse(Uri.parse('/'), '!space:server'),
        );
        u = Uri.parse(WorkspaceNav.openCoursePage(u, 'invite'));
        final l = layoutOf(u, 400, columnMode: false);
        // coursepage is appended AFTER course in the left list; the leaf rule
        // must still seat the page, not the card.
        expect(visOf(l, u, PanelTypesEnum.coursepage), PanelVis.full);
        expect(visOf(l, u, PanelTypesEnum.course), PanelVis.hidden);
      },
    );

    test('a genuinely new panel is still promoted (narrow)', () {
      // Replay every URL transition so recency builds as it does per-build in the
      // real shell (each build syncs once).
      var u = Uri.parse(
        WorkspaceNav.openLeft(
          Uri.parse('/'),
          const PanelToken(PanelTypesEnum.room, RoomTokenParam(id: '!abc')),
        ),
      );
      layoutOf(u, 400, columnMode: false); // build 1: room
      u = Uri.parse(WorkspaceNav.openSettings(u));
      final l = layoutOf(u, 400, columnMode: false); // build 2: + settings
      expect(visOf(l, u, PanelTypesEnum.settings), PanelVis.full);
      expect(visOf(l, u, PanelTypesEnum.room), PanelVis.hidden);
    });

    test('switching to a different room is promoted (distinct identity)', () {
      var u = Uri.parse(WorkspaceNav.openSettings(Uri.parse('/')));
      layoutOf(u, 400, columnMode: false); // build 1: settings
      u = Uri.parse(
        WorkspaceNav.openLeft(
          u,
          const PanelToken(PanelTypesEnum.room, RoomTokenParam(id: '!abc')),
        ),
      );
      layoutOf(u, 400, columnMode: false); // build 2: + room abc
      u = Uri.parse(
        WorkspaceNav.openExclusiveLeftRoom(
          u,
          const PanelToken(PanelTypesEnum.room, RoomTokenParam(id: '!xyz')),
        ),
      );
      final l = layoutOf(u, 400, columnMode: false); // build 3: swap to xyz
      expect(visOf(l, u, PanelTypesEnum.room), PanelVis.full); // the !xyz room
      expect(visOf(l, u, PanelTypesEnum.settings), PanelVis.hidden);
    });
  });
}
