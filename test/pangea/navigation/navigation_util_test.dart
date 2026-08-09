import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/utils/navigation_util.dart';

/// Guards the activity-plan → session "sibling replace" rule: starting or
/// continuing a session must REPLACE the activity plan, never open beside it.
/// The plan is a `left=activity:` token whose fields carry its session
/// bindings (route_facts.activityInfoFor); [NavigationUtil.stripActivityOverlay]
/// drops it (and collapses a shareable `/<uuid>` path that has not hit the
/// redirect yet) so the room token seats on the world path with no plan left
/// standing.
void main() {
  Uri u(String s) => Uri.parse(s);
  const activityId = 'af10c236-e094-4af3-9c0c-2226c5eb615b';

  group('stripActivityOverlay', () {
    test('collapses a standalone-activity path (share link) to the world '
        'path', () {
      final stripped = NavigationUtil.stripActivityOverlay(u('/$activityId'));
      expect(stripped.path, '/');
      expect(stripped.pathSegments, isEmpty);
    });

    test('drops the activity token, keeps the context and other panels', () {
      final stripped = NavigationUtil.stripActivityOverlay(
        u('/?c=!s&left=course,activity:$activityId.l'),
      );
      expect(stripped.path, '/');
      expect(stripped.query, 'c=!s&left=course');
    });

    test('drops an activity token with a bound session room', () {
      final stripped = NavigationUtil.stripActivityOverlay(
        u('/?left=activity:$activityId.r!r'),
      );
      expect(stripped.query, '');
    });

    test('is a no-op for a plain workspace url (no activity open)', () {
      final stripped = NavigationUtil.stripActivityOverlay(u('/?left=chats'));
      expect(stripped.path, '/');
      expect(stripped.query, 'left=chats');
    });
  });

  group('session replaces plan (end to end through the room funnel)', () {
    test(
      'from a share link: room seats on `/` with no plan path left standing',
      () {
        final loc = WorkspaceNav.openExclusiveLeftRoom(
          NavigationUtil.stripActivityOverlay(u('/$activityId')),
          RoomPanelToken(RoomTokenParam.parse('!abc')),
        );
        final result = u(loc);
        expect(result.pathSegments, isEmpty, reason: 'no `/<uuid>` plan path');
        expect(parseOpenPanels(result).left, [
          RoomPanelToken(RoomTokenParam.parse('!abc')),
        ]);
      },
    );

    test('from a course: room replaces the plan, course context survives', () {
      final loc = WorkspaceNav.openExclusiveLeftRoom(
        NavigationUtil.stripActivityOverlay(
          u('/?c=!s&left=course,activity:$activityId.l'),
        ),
        RoomPanelToken(RoomTokenParam.parse('!abc')),
      );
      final result = u(loc);
      expect(result.path, '/');
      expect(result.query.contains('activity'), isFalse);
      expect(result.query.contains('c=!s'), isTrue);
      expect(parseOpenPanels(result).left, [
        const CoursePanelToken(),
        RoomPanelToken(RoomTokenParam.parse('!abc')),
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
      expect(
        NavigationUtil.coursePageFor('details/invite'),
        RoomSubpageEnum.invite,
      );
      expect(
        NavigationUtil.coursePageFor('details/permissions'),
        RoomSubpageEnum.permissions,
      );
    });

    test('bare `details` maps to null room subpage', () {
      expect(NavigationUtil.coursePageFor('details'), null);
    });

    test('an already-bare course page passes through unchanged', () {
      expect(NavigationUtil.coursePageFor('invite'), RoomSubpageEnum.invite);
      expect(NavigationUtil.coursePageFor('edit'), RoomSubpageEnum.edit);
      expect(NavigationUtil.coursePageFor(''), null);
    });

    test(
      'end to end: a participants-tab invite seats a renderable coursepage',
      () {
        // The participants tab calls goToSpaceRoute(space, ['details','invite']);
        // through the course-space branch that is openCoursePage(.., 'invite').
        final loc = WorkspaceNav.openCoursePage(
          u('/?c=!s&left=course'),
          NavigationUtil.coursePageFor('details/invite'),
        );
        final coursepage = parseOpenPanels(
          u(loc),
        ).left.where((t) => t.type == PanelTypesEnum.coursepage).single;
        // The renderable token — NOT the blank `coursepage:details/invite`.
        expect(
          coursepage,
          CoursePagePanelToken(RoomSubpageTokenParam.parse('invite')),
        );
      },
    );
  });
}
