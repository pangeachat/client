import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_background.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_visibility.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_visibility_target.dart';

/// #9440 — the opt-in activity image behind an activity chat fades in as the
/// carousel scrolls out of view, so the two never show at once.
void main() {
  // The background checks its URL against the CMS host, read from dotenv.
  setUpAll(() => dotenv.testLoad(mergeWith: <String, String>{}));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    // AppSettings keeps the store from the first init, so reset between tests.
    await AppSettings.activityImageAsChatBackground.setItem(false);
  });

  // The test viewport is 600 tall: the 200-tall carousel sits at the top of a
  // list long enough to scroll it away, like the chat timeline.
  const carouselHeight = 200.0;

  late ActivityMediaVisibility visibility;
  late ScrollController scrollController;

  Future<void> pumpChat(WidgetTester tester) async {
    visibility = ActivityMediaVisibility();
    scrollController = ScrollController();
    addTearDown(visibility.dispose);
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: ActivityChatBackground(
                  imageUrl: Uri.parse('https://example.com/scene.jpg'),
                  blur: 0,
                  mediaVisibility: visibility,
                  scrollController: scrollController,
                ),
              ),
              ListView.builder(
                controller: scrollController,
                itemCount: 100,
                itemBuilder: (context, i) => i == 0
                    ? ActivityMediaVisibilityTarget(
                        visibility: visibility,
                        child: const SizedBox(height: carouselHeight),
                      )
                    : const SizedBox(height: 100),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double? backgroundOpacity(WidgetTester tester) {
    final fade = find.descendant(
      of: find.byType(ActivityChatBackground),
      matching: find.byType(AnimatedOpacity),
    );
    if (fade.evaluate().isEmpty) return null;
    return tester.widget<AnimatedOpacity>(fade).opacity;
  }

  Future<void> scrollTo(WidgetTester tester, double offset) async {
    scrollController.jumpTo(offset);
    await tester.pumpAndSettle();
  }

  testWidgets('off by default: nothing is drawn behind the chat', (
    tester,
  ) async {
    await pumpChat(tester);
    await scrollTo(tester, 2000);

    expect(backgroundOpacity(tester), isNull);
  });

  testWidgets('follows how much of the carousel has scrolled away', (
    tester,
  ) async {
    await AppSettings.activityImageAsChatBackground.setItem(true);
    await pumpChat(tester);

    // Carousel fully on screen: plain background.
    expect(backgroundOpacity(tester), 0);

    await scrollTo(tester, carouselHeight / 2);
    expect(backgroundOpacity(tester), closeTo(0.5, 0.001));

    // Scrolled far enough that the list drops the carousel entirely.
    await scrollTo(tester, 5000);
    expect(backgroundOpacity(tester), 1);

    await scrollTo(tester, 0);
    expect(backgroundOpacity(tester), 0);
  });

  testWidgets('turning it on in an open chat fades the image in', (
    tester,
  ) async {
    await pumpChat(tester);
    await scrollTo(tester, 2000);
    expect(backgroundOpacity(tester), isNull);

    await AppSettings.activityImageAsChatBackground.setItem(true);
    await tester.pump();
    // Starts hidden rather than appearing at full strength...
    expect(backgroundOpacity(tester), 0);
    await tester.pumpAndSettle();
    // ...then settles at the carousel's actual position: off screen.
    expect(backgroundOpacity(tester), 1);

    await AppSettings.activityImageAsChatBackground.setItem(false);
    await tester.pumpAndSettle();
    expect(backgroundOpacity(tester), isNull);

    // Turned on again, it fades in again rather than reusing the old position.
    await AppSettings.activityImageAsChatBackground.setItem(true);
    await tester.pump();
    expect(backgroundOpacity(tester), 0);
    await tester.pumpAndSettle();
    expect(backgroundOpacity(tester), 1);
  });

  testWidgets('another setting changing leaves the background alone', (
    tester,
  ) async {
    await AppSettings.activityImageAsChatBackground.setItem(true);
    await pumpChat(tester);
    await scrollTo(tester, 2000);
    expect(backgroundOpacity(tester), 1);

    await AppSettings.sendOnEnter.setItem(true);
    await tester.pump();

    expect(backgroundOpacity(tester), 1);
  });
}
