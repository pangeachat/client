import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goals_dropdown.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_start_hero.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_close_button.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';
import 'activity_session_fixtures.dart';
import 'one_node_control.dart';

/// No goals: the goals dropdown stays mounted as an overlay but renders
/// nothing, so it reads nothing from the app's controllers.
class _BareSession implements ActivitySessionStateController {
  @override
  final bool showRoleCards;

  _BareSession({this.showRoleCards = false});

  @override
  List<ActivityRoleGoal>? get selectedRoleGoals => null;
  @override
  Set<String> get selectedRoleCompletedGoalIds => const {};
  @override
  bool get goalsStartCollapsed => false;
  @override
  bool get showDescriptionSection => false;
  @override
  String? get descriptionText => null;
  @override
  double get roleCardOpacity => 1.0;
  @override
  bool isRoleSelected(String id) => false;
  @override
  bool isRoleShimmering(String id) => false;
  @override
  bool canSelectRole(String id) => false;
  @override
  void selectRole(String id) {}
  @override
  bool showStarsCard(String id) => false;
  @override
  Set<String> completedGoalIdsForRole(String id) => const {};
}

/// The start page with no session room, course or tutorial: what the role
/// cards read from it, without a mounted page or Matrix client.
class _RoomlessStartState extends ActivitySessionStartState {
  @override
  Room? get activityRoom => null;
  @override
  Room? get courseParent => null;
  @override
  Map<String, ActivityRoleModel> get assignedRoles => const {};
  @override
  String? get activityRolesTargetId => null;
  @override
  void onTutorialSurfaceChanged() {}
}

/// #9351 — tapping an image hero fades the overlays and shows the whole image,
/// as tapping a video hero does for the clip.
void main() {
  // ImageByUrl checks each URL against the CMS host, which Environment reads
  // from dotenv.
  setUpAll(() => dotenv.testLoad(mergeWith: <String, String>{}));

  // Hosts outside AppConfig's image allow-list render a blurhash, so the test
  // needs no network.
  const image = ActivityMediaBlock(
    blockType: 'image',
    resolvedUrl: 'https://example.com/full.jpg',
  );
  const video = ActivityMediaBlock(
    blockType: 'video',
    resolvedUrl: 'https://example.com/clip.mp4',
    resolvedThumbnailUrl: 'https://example.com/poster.jpg',
  );

  Future<void> pumpHero(
    WidgetTester tester,
    List<ActivityMediaBlock> media, {
    bool settle = true,
    bool showRoleCards = false,
  }) async {
    final activity = twoRoleActivityPlan().withMedia(media);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          // The start page's scroll view: the hero sizes to its content.
          body: ListView(
            children: [
              ActivityStartHero(
                controller: _RoomlessStartState(),
                sessionController: _BareSession(showRoleCards: showRoleCards),
                activity: activity,
              ),
              const Text('Below the hero'),
            ],
          ),
        ),
      ),
    );
    // The no-media placeholder is an allowed host, and its loading shimmer
    // never settles.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  // Built per use: a semantics finder needs the binding, which a test starts.
  Finder viewImage() => find.bySemanticsLabel('View image');
  Finder close() => find.byType(ActivityVideoCloseButton);

  BoxFit imageFit(WidgetTester tester) =>
      tester.widget<ImageByUrl>(find.byType(ImageByUrl)).fit;

  bool? announcedExpanded(WidgetTester tester) {
    final flag = tester
        .getSemantics(viewImage())
        .getSemanticsData()
        .flagsCollection
        .isExpanded;
    return flag.toBoolOrNull();
  }

  void expectCollapsed(WidgetTester tester) {
    expect(find.byType(ActivityGoalsDropdown), findsOneWidget);
    expect(close(), findsNothing);
    expect(imageFit(tester), BoxFit.cover);
    expect(announcedExpanded(tester), isFalse);
  }

  void expectExpanded(WidgetTester tester) {
    expect(find.byType(ActivityGoalsDropdown), findsNothing);
    expect(close(), findsOneWidget);
    expect(imageFit(tester), BoxFit.contain);
    expect(announcedExpanded(tester), isTrue);
  }

  testWidgets('an image hero is one button named View image', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHero(tester, const [image]);

    expectOneNodeControl(tester, 'View image');
    expectCollapsed(tester);
    handle.dispose();
  });

  testWidgets('tapping the image shows it whole; the close control restores', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHero(tester, const [image]);

    await tester.tap(viewImage());
    await tester.pumpAndSettle();
    expectExpanded(tester);

    await tester.tap(close());
    await tester.pumpAndSettle();
    expectCollapsed(tester);
    handle.dispose();
  });

  testWidgets('tapping the open image again restores', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHero(tester, const [image]);

    await tester.tap(viewImage());
    await tester.pumpAndSettle();
    expectExpanded(tester);

    await tester.tap(viewImage());
    await tester.pumpAndSettle();
    expectCollapsed(tester);
    handle.dispose();
  });

  testWidgets('the keyboard toggles the image and keeps focus on it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHero(tester, const [image]);

    bool imageFocused() =>
        tester.getSemantics(viewImage()).flagsCollection.isFocused ==
        Tristate.isTrue;

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(imageFocused(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expectExpanded(tester);
    expect(imageFocused(), isTrue, reason: 'Enter keeps focus on the image');

    // The close strip sits above the image, so it is the previous Tab stop.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();
    expect(imageFocused(), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expectCollapsed(tester);
    expect(imageFocused(), isTrue, reason: 'closing returns focus to it');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expectExpanded(tester);
    handle.dispose();
  });

  // The role cards make the hero taller than its image. Removing them once
  // they have faded must not pull the page below up, nor push it back down
  // when they return.
  testWidgets(
    'the text below the hero stays put as the image opens and closes',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHero(tester, const [image], showRoleCards: true);
      final below = find.text('Below the hero');
      final start = tester.getTopLeft(below);
      expect(
        start.dy,
        greaterThan(375.0),
        reason: 'role cards extend the hero',
      );

      Future<void> expectBelowStill(String when) async {
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getTopLeft(below), start, reason: 'mid-fade $when');
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(below), start, reason: 'after $when');
      }

      await tester.tap(viewImage());
      await expectBelowStill('opening');
      expectExpanded(tester);

      await tester.tap(close());
      await expectBelowStill('closing');
      expectCollapsed(tester);
      handle.dispose();
    },
  );

  testWidgets('a video hero still offers Play video, not View image', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHero(tester, const [video]);

    expectOneNodeControl(tester, 'Play video');
    expect(viewImage(), findsNothing);
    handle.dispose();
  });

  testWidgets('an activity with no media offers nothing to open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHero(tester, const [], settle: false);

    expect(find.byType(ImageByUrl), findsOneWidget, reason: 'the hero drew');
    expect(viewImage(), findsNothing);
    expect(find.bySemanticsLabel('Play video'), findsNothing);
    handle.dispose();
  });
}
