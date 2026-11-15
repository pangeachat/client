import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_entry_intent.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';
import 'package:fluffychat/utils/navigation_util.dart';

/// #9632 — an activity opened from the course card takes the card's place,
/// and the session started from it takes the activity's. Closing that session
/// gives the place back to the card, on the activity's Mission, which rides
/// the URL (`?mission=`) the whole way. Sessions opened any other way close as
/// before (routing.instructions.md → Closing a panel: X or back arrow).
void main() {
  Uri u(String s) => Uri.parse(s);
  List<PanelTypesEnum> leftTypes(Uri uri) =>
      parseOpenPanels(uri).left.map((t) => t.type).toList();

  /// A session the course card opened, alone in its column, with the Mission
  /// it was started under.
  const sessionFromCard = '/?c=!s&mission=lo-2&left=room:!sess.c';

  group('the course-card origin rides the tokens', () {
    test('an activity opened from the card round-trips the mark', () {
      const fromCard = ActivityTokenParam(
        activityId: 'act-1',
        launch: true,
        fromCourseCard: true,
      );
      final parsed = ActivityTokenParam.parse(fromCard.build());
      expect(parsed.fromCourseCard, isTrue);
      expect(parsed.launch, isTrue);
      expect(parsed, fromCard);
      expect(
        parsed,
        isNot(const ActivityTokenParam(activityId: 'act-1', launch: true)),
      );
    });

    test('a session the card opened round-trips the mark, bare and with a '
        'sub-page, a filter or a jump', () {
      final shapes = [
        const RoomTokenParam(id: '!sess', fromCourseCard: true),
        const RoomTokenParam(
          id: '!sess',
          subpage: 'details',
          fromCourseCard: true,
        ),
        const RoomTokenParam(
          id: '!sess',
          subpage: 'invite',
          filter: InvitationFilter.knocking,
          fromCourseCard: true,
        ),
        const RoomTokenParam(
          id: '!sess',
          eventId: r'$ev:server.org',
          fromCourseCard: true,
        ),
      ];
      for (final param in shapes) {
        final parsed = RoomTokenParam.parse(param.build());
        expect(parsed, param, reason: param.build());
        expect(parsed.id, '!sess', reason: param.build());
      }
      expect(shapes.first.build(), '!sess.c');
      expect(
        RoomTokenParam.parse('!sess'),
        isNot(shapes.first),
        reason: 'the mark counts in equality',
      );
    });

    test('a room id with dots in its server name is not read as marked', () {
      final parsed = RoomTokenParam.parse('!abc:example.org/search');
      expect(parsed.id, '!abc:example.org');
      expect(parsed.fromCourseCard, isFalse);
    });

    test('popping a sub-page keeps the mark', () {
      const page = RoomTokenParam(
        id: '!sess',
        subpage: 'search',
        fromCourseCard: true,
      );
      expect(
        page.poppedParam,
        const RoomTokenParam(id: '!sess', fromCourseCard: true),
      );
    });
  });

  group('Start keeps where the plan was opened from, and its Mission', () {
    test('a plan the card opened launches marked, on the picked Mission', () {
      final plan = u(
        WorkspaceNav.selectMission(
          u(
            WorkspaceNav.openCourseActivity(
              '!s',
              'act-1',
              fromCoursePlan: true,
              fromCourseCard: true,
            ),
          ),
          'lo-2',
        ),
      );
      final launched = u(
        WorkspaceNav.launchCourseActivity(plan, '!s', 'act-1'),
      );
      expect(activityInfoFor(launched), isNotNull);
      expect(activityInfoFor(launched)!.launch, isTrue);
      expect(activityInfoFor(launched)!.fromCourseCard, isTrue);
      expect(activityInfoFor(launched)!.fromCoursePlan, isTrue);
      expect(selectedMissionIdFor(launched), 'lo-2');
      expect(activeSpaceIdFor(launched), '!s');
    });

    test('a plan opened any other way launches unmarked', () {
      final launched = u(
        WorkspaceNav.launchCourseActivity(
          u('/?c=!s&mission=lo-2&left=activity:act-1'),
          '!s',
          'act-1',
        ),
      );
      expect(activityInfoFor(launched)!.fromCourseCard, isFalse);
      expect(activityInfoFor(launched)!.fromCoursePlan, isFalse);
      expect(
        selectedMissionIdFor(launched),
        'lo-2',
        reason: 'the course is the same, so its picked Mission stays',
      );
    });

    test('a launch into another course drops the old course\'s Mission', () {
      final launched = u(
        WorkspaceNav.launchCourseActivity(
          u('/?c=!other&mission=lo-2&left=activity:act-1.c'),
          '!s',
          'act-1',
        ),
      );
      expect(activeSpaceIdFor(launched), '!s');
      expect(selectedMissionIdFor(launched), isNull);
    });

    test('viewing a session from the join list and backing out keep the '
        'mark', () {
      final plan = u(
        WorkspaceNav.openCourseActivity('!s', 'act-1', fromCourseCard: true),
      );
      final viewing = u(
        WorkspaceNav.openActivitySession(plan, 'act-1', '!sess'),
      );
      expect(activityInfoFor(viewing)!.fromCourseCard, isTrue);
      final back = u(WorkspaceNav.closeActivitySession(viewing, 'act-1'));
      expect(activityInfoFor(back)!.fromCourseCard, isTrue);
    });
  });

  group('closing a session', () {
    test('one reopened from the card\'s full plan reopens the card, on its '
        'Mission, not the plan underneath', () {
      final reopened = u(
        WorkspaceNav.selectMission(
          u(
            WorkspaceNav.openCourseSession(
              u('/?c=!s&left=course,coursepage:plan&right=analytics:vocab'),
              '!sess',
            ),
          ),
          'lo-2',
        ),
      );
      expect(leftTypes(reopened), [PanelTypesEnum.room]);
      expect(reopened.queryParameters['right'], 'analytics:vocab');

      final closed = u(roomTokenCloseLocation(reopened, '!sess')!);
      expect(leftTypes(closed), [PanelTypesEnum.course]);
      expect(selectedMissionIdFor(closed), 'lo-2');
      expect(activeSpaceIdFor(closed), '!s');
    });

    test('one the card opened reopens the card, on its Mission', () {
      final closed = u(roomTokenCloseLocation(u(sessionFromCard), '!sess')!);
      expect(leftTypes(closed), [PanelTypesEnum.course]);
      expect(selectedMissionIdFor(closed), 'lo-2');
      expect(activeSpaceIdFor(closed), '!s');
      expect(
        closeReopensCourseCard(u(sessionFromCard), closed.toString()),
        isTrue,
      );
    });

    test('the right column is left as it was', () {
      final closed = u(
        roomTokenCloseLocation(
          u('$sessionFromCard&right=analytics:vocab'),
          '!sess',
        )!,
      );
      expect(leftTypes(closed), [PanelTypesEnum.course]);
      expect(closed.queryParameters['right'], 'analytics:vocab');
    });

    test('one opened any other way closes to the bare course context, as '
        'before', () {
      const other = '/?c=!s&mission=lo-2&left=room:!sess';
      final closed = u(roomTokenCloseLocation(u(other), '!sess')!);
      expect(leftTypes(closed), isEmpty);
      expect(selectedMissionIdFor(closed), 'lo-2');
      expect(closeReopensCourseCard(u(other), closed.toString()), isFalse);
    });

    test('with another left panel open, that panel is what it reveals', () {
      final closed = u(
        roomTokenCloseLocation(u('/?c=!s&left=chats,room:!sess.c'), '!sess')!,
      );
      expect(leftTypes(closed), [PanelTypesEnum.chats]);
    });

    test('with the card already open beside it, the card stays', () {
      final closed = u(
        roomTokenCloseLocation(u('/?c=!s&left=room:!sess.c,course'), '!sess')!,
      );
      expect(leftTypes(closed), [PanelTypesEnum.course]);
    });

    test('with no course context left, there is no card to reopen', () {
      final closed = u(
        roomTokenCloseLocation(u('/?left=room:!sess.c'), '!sess')!,
      );
      expect(leftTypes(closed), isEmpty);
    });
  });

  /// Pump a GoRouter at [initialLocation], tap a button that runs [onTap]
  /// with an in-router context, and return where the router settles.
  Future<Uri> tapFrom(
    WidgetTester tester,
    String initialLocation,
    void Function(BuildContext) onTap,
  ) async {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => onTap(context),
              child: const Text('go'),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return router.routerDelegate.currentConfiguration.uri;
  }

  group('through the room funnel', () {
    testWidgets('the session started from a plan the card opened replaces it '
        'marked, on the same Mission', (tester) async {
      final uri = await tapFrom(
        tester,
        '/?c=!s&mission=lo-2&left=activity:act-1.l.c',
        (c) => NavigationUtil.goToSpaceRoute('!sess', const [], c),
      );
      expect(parseOpenPanels(uri).left, [
        const RoomPanelToken(RoomTokenParam(id: '!sess', fromCourseCard: true)),
      ]);
      expect(selectedMissionIdFor(uri), 'lo-2');
    });

    testWidgets('a session started from an unmarked plan opens unmarked', (
      tester,
    ) async {
      final uri = await tapFrom(
        tester,
        '/?c=!s&left=activity:act-1.l',
        (c) => NavigationUtil.goToSpaceRoute('!sess', const [], c),
      );
      expect(parseOpenPanels(uri).left, [
        const RoomPanelToken(RoomTokenParam(id: '!sess')),
      ]);
    });

    testWidgets('a sub-page of the marked session keeps the mark', (
      tester,
    ) async {
      final uri = await tapFrom(
        tester,
        sessionFromCard,
        (c) => NavigationUtil.goToSpaceRoute('!sess', const ['details'], c),
      );
      expect(parseOpenPanels(uri).left, [
        const RoomPanelToken(
          RoomTokenParam(id: '!sess', subpage: 'details', fromCourseCard: true),
        ),
      ]);
    });

    testWidgets('leaving the marked session from its own menu reopens the '
        'card', (tester) async {
      final uri = await tapFrom(
        tester,
        sessionFromCard,
        (c) => closeOwnRoomPanel(c, '!sess'),
      );
      expect(leftTypes(uri), [PanelTypesEnum.course]);
      expect(selectedMissionIdFor(uri), 'lo-2');
    });
  });

  testWidgets('the session\'s X reopens the card and hands it focus, even '
      'from a stale unmarked token', (tester) async {
    final router = GoRouter(
      initialLocation: sessionFromCard,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: LeftPanelCloseButton(
              token: RoomPanelToken(RoomTokenParam.parse('!sess')),
              currentUri: state.uri,
              foldedOver: false,
              isColumnMode: true,
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    // Clear any arm left by an earlier test.
    PanelEntryIntent.instance.take();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    final uri = router.routerDelegate.currentConfiguration.uri;
    expect(leftTypes(uri), [PanelTypesEnum.course]);
    expect(selectedMissionIdFor(uri), 'lo-2');
    expect(
      PanelEntryIntent.instance.take(),
      isTrue,
      reason: 'the card that mounts claims focus',
    );
  });
}
