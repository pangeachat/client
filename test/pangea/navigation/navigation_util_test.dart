import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/utils/navigation_util.dart';

/// Guards the activity-plan → session "sibling replace" rule: starting or
/// continuing a session must REPLACE the activity plan, never open beside it.
/// The plan is addressed two ways (route_facts.activityFor): the in-course
/// `?activity=` query overlay AND the parentless standalone `/<uuid>` path
/// (opened from a map pin). [NavigationUtil.stripActivityOverlay] must clear
/// BOTH so the room token seats on the world path with no plan left standing.
void main() {
  Uri u(String s) => Uri.parse(s);
  const activityId = 'af10c236-e094-4af3-9c0c-2226c5eb615b';

  group('stripActivityOverlay', () {
    test('collapses a standalone-activity path (map pin) to the world path', () {
      // The bug: `/<uuid>?launch=true` kept the `/<uuid>` path, so a `left=room`
      // opened beside the plan (which renders from that path).
      final stripped = NavigationUtil.stripActivityOverlay(
        u('/$activityId?launch=true'),
      );
      expect(stripped.path, '/');
      expect(stripped.pathSegments, isEmpty);
      expect(stripped.query, '');
    });

    test('collapses a standalone-activity path with no query', () {
      final stripped = NavigationUtil.stripActivityOverlay(u('/$activityId'));
      expect(stripped.path, '/');
      expect(stripped.pathSegments, isEmpty);
    });

    test(
      'drops the in-course `?activity=` overlay params, keeps m=/left= raw',
      () {
        final stripped = NavigationUtil.stripActivityOverlay(
          u('/?m=course:!s&left=course&activity=$activityId&launch=true'),
        );
        expect(stripped.path, '/');
        // m= and left= survive verbatim (raw, not re-encoded); activity/launch go.
        expect(stripped.query, 'm=course:!s&left=course');
      },
    );

    test('drops a continue roomid param', () {
      final stripped = NavigationUtil.stripActivityOverlay(
        u('/?activity=$activityId&roomid=!r'),
      );
      expect(stripped.query, '');
    });

    test('is a no-op for a plain workspace url (no activity addressing)', () {
      final stripped = NavigationUtil.stripActivityOverlay(u('/?left=chats'));
      expect(stripped.path, '/');
      expect(stripped.query, 'left=chats');
    });
  });

  group('session replaces plan (end to end through the room funnel)', () {
    test(
      'from a map pin: room seats on `/` with no plan path left standing',
      () {
        final loc = WorkspaceNav.openExclusiveLeftRoom(
          NavigationUtil.stripActivityOverlay(u('/$activityId?launch=true')),
          const PanelToken('room', '!abc'),
        );
        final result = u(loc);
        expect(result.pathSegments, isEmpty, reason: 'no `/<uuid>` plan path');
        expect(parseOpenPanels(result).left, [
          const PanelToken('room', '!abc'),
        ]);
      },
    );

    test('from a course: room replaces the plan, course filter survives', () {
      final loc = WorkspaceNav.openExclusiveLeftRoom(
        NavigationUtil.stripActivityOverlay(
          u('/?m=course:!s&left=course&activity=$activityId&launch=true'),
        ),
        const PanelToken('room', '!abc'),
      );
      final result = u(loc);
      expect(result.path, '/');
      expect(result.query.contains('activity='), isFalse);
      expect(result.query.contains('m=course:!s'), isTrue);
      expect(parseOpenPanels(result).left, [
        const PanelToken('course'),
        const PanelToken('room', '!abc'),
      ]);
    });
  });

  /// Guards #7099: the chat-details UI (participants tab, button row) addresses
  /// course-space management screens with a room-style `details/<page>`
  /// subroute, but a course has no `details` coursepage. Before the fix this
  /// produced the unhandled token `coursepage:details/invite`, which the left
  /// panel rendered as an empty, un-closable `SizedBox.shrink()`.
  /// [NavigationUtil.coursePageFor] normalizes the subroute so the coursepage
  /// is one the renderer actually handles.
  group('coursePageFor (room-style subroute → course page)', () {
    test('details/<page> drops the room-only `details` segment', () {
      expect(NavigationUtil.coursePageFor('details/invite'), 'invite');
      expect(
        NavigationUtil.coursePageFor('details/permissions'),
        'permissions',
      );
    });

    test('bare `details` maps to the card (empty page)', () {
      expect(NavigationUtil.coursePageFor('details'), '');
    });

    test('an already-bare course page passes through unchanged', () {
      expect(NavigationUtil.coursePageFor('invite'), 'invite');
      expect(NavigationUtil.coursePageFor('edit'), 'edit');
      expect(NavigationUtil.coursePageFor(''), '');
    });

    test(
      'end to end: a participants-tab invite seats a renderable coursepage',
      () {
        // The participants tab calls goToSpaceRoute(space, ['details','invite']);
        // through the course-space branch that is openCoursePage(.., 'invite').
        final loc = WorkspaceNav.openCoursePage(
          u('/?m=course:!s&left=course'),
          NavigationUtil.coursePageFor('details/invite'),
        );
        final coursepage = parseOpenPanels(
          u(loc),
        ).left.where((t) => t.type == 'coursepage').single;
        // The renderable token — NOT the blank `coursepage:details/invite`.
        expect(coursepage, const PanelToken('coursepage', 'invite'));
      },
    );
  });
}
