import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/mobile_nav_widget.dart';

/// Coverage for the world_v2 single-column bottom chrome: one floating
/// rounded-corner box combining the 4-item nav rail with an expandable cavity
/// above it. Generalizes `MobileCourseSheet`'s per-key static height memory
/// (#7332) and its #7128 Semantics-labeled drag handle to three rest states
/// (collapsed / half / full) and any section or course key. See
/// "Single-column bottom nav" in routing.instructions.md.
void main() {
  // Each test starts from a clean height-memory so a prior test's expanded
  // key doesn't leak into the next widget's initial height.
  setUp(MobileNavWidget.resetHeightMemoryForTest);

  Future<void> pumpNav(
    WidgetTester tester, {
    AppSection activeSection = AppSection.world,
    Widget? cavityChild,
    String? cavityKey,
    bool cavityDefaultsToPeek = false,
    void Function(AppSection section)? onSectionTap,
    VoidCallback? onCourseShortcutTap,
    double maxHeightFraction = 0.75,
    double? preferredCavityHeightPx,
    AppSection? cavitySection,
    bool courseShortcutHostsCavity = false,
    VoidCallback? onDismissed,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: MobileNavWidget(
            activeSection: activeSection,
            courseShortcutIcon: const Icon(Icons.add),
            courseShortcutLabel: 'Add a course',
            onCourseShortcutTap: onCourseShortcutTap ?? () {},
            onSectionTap: onSectionTap ?? (_) {},
            cavityChild: cavityChild,
            cavityKey: cavityKey,
            cavityDefaultsToPeek: cavityDefaultsToPeek,
            maxHeightFraction: maxHeightFraction,
            preferredCavityHeightPx: preferredCavityHeightPx,
            cavitySection: cavitySection,
            courseShortcutHostsCavity: courseShortcutHostsCavity,
            onDismissed: onDismissed,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Drop the widget from the tree (as a full-screen surface mounting over it
  // does), disposing its State, so the next pumpNav is a genuinely fresh mount.
  Future<void> unmountNav(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder handleFinder() => find.byWidgetPredicate(
    (w) =>
        w is GestureDetector &&
        w.onVerticalDragUpdate != null &&
        w.onTap != null,
  );

  double cavityHeightOf(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final constraints = container.constraints;
    return container.decoration == null && constraints == null
        ? 0.0
        : (container.constraints?.maxHeight ?? 0.0);
  }

  group('rail', () {
    testWidgets('renders 4 items and highlights the active section', (
      tester,
    ) async {
      await pumpNav(tester, activeSection: AppSection.chats);

      // World (Pangea logo button), Chats, Courses (map icon), course shortcut.
      final worldButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('World'),
          matching: find.byType(IconButton),
        ),
      );
      final chatsButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('All chats'),
          matching: find.byType(IconButton),
        ),
      );
      final coursesButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Courses'),
          matching: find.byType(IconButton),
        ),
      );

      expect(worldButton.isSelected, isFalse);
      expect(chatsButton.isSelected, isTrue);
      expect(coursesButton.isSelected, isFalse);

      // The course shortcut renders too (4th item), addressed by its label.
      expect(find.byTooltip('Add a course'), findsOneWidget);
    });

    testWidgets('section taps invoke onSectionTap with the right section', (
      tester,
    ) async {
      final tapped = <AppSection>[];
      await pumpNav(
        tester,
        activeSection: AppSection.world,
        onSectionTap: tapped.add,
      );

      await tester.tap(find.byTooltip('All chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Courses'));
      await tester.pumpAndSettle();

      expect(tapped, [AppSection.chats, AppSection.courses]);
    });

    testWidgets('course shortcut tap invokes onCourseShortcutTap', (
      tester,
    ) async {
      var tapped = false;
      await pumpNav(tester, onCourseShortcutTap: () => tapped = true);

      await tester.tap(find.byTooltip('Add a course'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });

  group('cavity open height', () {
    testWidgets('a section cavity opens at half height by default', (
      tester,
    ) async {
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        cavityDefaultsToPeek: false,
        maxHeightFraction: 0.75,
      );

      final screenHeight = 800.0;
      final maxHeightPx = screenHeight * 0.75;
      expect(cavityHeightOf(tester), closeTo(maxHeightPx * 0.5, 1.0));
    });

    testWidgets('a content-fit preferred height replaces half as the '
        'default open height', (tester) async {
      // The chats sheet opens showing all its chats: the shell passes the
      // content height and the cavity opens exactly there, not at 0.5.
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
        preferredCavityHeightPx: 240.0,
      );
      expect(cavityHeightOf(tester), closeTo(240.0, 1.0));
    });

    testWidgets('a preferred height beyond the cap clamps to the cap', (
      tester,
    ) async {
      // Long chat list: the fit height exceeds the space below the analytics
      // bar, so the sheet opens at the cap and scrolls.
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
        preferredCavityHeightPx: 5000.0,
      );
      final maxHeightPx = 800.0 * 0.75;
      expect(cavityHeightOf(tester), closeTo(maxHeightPx, 1.0));
    });

    testWidgets('a course cavity opens at a small peek by default', (
      tester,
    ) async {
      await pumpNav(
        tester,
        activeSection: AppSection.courses,
        cavityChild: const Text('Course card'),
        cavityKey: 'course-a',
        cavityDefaultsToPeek: true,
        maxHeightFraction: 0.75,
      );

      final maxHeightPx = 800.0 * 0.75;
      final height = cavityHeightOf(tester);
      // The designed 128px peek — the compact course header (title + progress
      // bar), tabs below the fold (#7597): above 0 (rail-only) and clearly
      // short of half. Before the rest state was derived per-build, a cold
      // mount resolved against a zero max height and rendered the 0.2 fallback
      // (120px) instead.
      expect(height, closeTo(128.0, 1.0));
      expect(height, lessThan(maxHeightPx * 0.5));
    });

    testWidgets(
      'a course cavity reopens at peek, not the height it was left at (#7609)',
      (tester) async {
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityDefaultsToPeek: true,
        );
        final peek = cavityHeightOf(tester);

        // Expand to full (tap-the-body, #7609), then leave.
        await tester.tap(find.text('Course card'));
        await tester.pumpAndSettle();
        expect(cavityHeightOf(tester), greaterThan(peek));
        await unmountNav(tester);

        // Reopening the same course arrives at the default peek — a
        // deterministic entry state; the height memory is section sheets'.
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityDefaultsToPeek: true,
        );
        expect(cavityHeightOf(tester), closeTo(peek, 1.0));
      },
    );

    testWidgets('tapping the sheet body at peek expands to full (#7609)', (
      tester,
    ) async {
      await pumpNav(
        tester,
        activeSection: AppSection.courses,
        cavityChild: const Text('Course card'),
        cavityKey: 'course-a',
        cavityDefaultsToPeek: true,
      );
      final peek = cavityHeightOf(tester);

      // The tap lands on the card content, not the handle or a button —
      // the cavity-wide detector claims it.
      await tester.tap(find.text('Course card'));
      await tester.pumpAndSettle();

      expect(cavityHeightOf(tester), closeTo(800.0 * 0.75, 1.0));
      expect(cavityHeightOf(tester), greaterThan(peek));
    });

    testWidgets(
      'tapping the sheet body while expanded does NOT collapse or fall '
      'through (#7609)',
      (tester) async {
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityDefaultsToPeek: true,
        );
        await tester.tap(find.text('Course card'));
        await tester.pumpAndSettle();
        final full = cavityHeightOf(tester);

        await tester.tap(find.text('Course card'));
        await tester.pumpAndSettle();

        expect(cavityHeightOf(tester), closeTo(full, 1.0));
      },
    );

    testWidgets('dragging the sheet body resizes, not just the handle '
        '(#7609)', (tester) async {
      await pumpNav(
        tester,
        activeSection: AppSection.courses,
        cavityChild: const Text('Course card'),
        cavityKey: 'course-a',
        cavityDefaultsToPeek: true,
      );
      final peek = cavityHeightOf(tester);

      await tester.drag(find.text('Course card'), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(cavityHeightOf(tester), greaterThan(peek));
    });
  });

  group('handle', () {
    testWidgets('tap toggles half <-> full', (tester) async {
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
      );

      final maxHeightPx = 800.0 * 0.75;
      expect(cavityHeightOf(tester), closeTo(maxHeightPx * 0.5, 1.0));

      await tester.tap(handleFinder());
      await tester.pumpAndSettle();
      expect(cavityHeightOf(tester), closeTo(maxHeightPx, 1.0));

      await tester.tap(handleFinder());
      await tester.pumpAndSettle();
      expect(cavityHeightOf(tester), closeTo(maxHeightPx * 0.5, 1.0));
    });

    testWidgets('drag up grows the cavity, drag down shrinks it', (
      tester,
    ) async {
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
      );

      final beforeUp = cavityHeightOf(tester);
      await tester.drag(handleFinder(), const Offset(0, -300));
      await tester.pumpAndSettle();
      final afterUp = cavityHeightOf(tester);
      expect(
        afterUp,
        greaterThan(beforeUp),
        reason: 'dragging the handle up must grow the cavity',
      );

      await tester.drag(handleFinder(), const Offset(0, 600));
      await tester.pumpAndSettle();
      final afterDown = cavityHeightOf(tester);
      expect(
        afterDown,
        lessThan(afterUp),
        reason: 'dragging the handle down must shrink the cavity',
      );
    });

    testWidgets(
      'a section sheet dragged fully down reopens at a real height (#7510)',
      (tester) async {
        await pumpNav(
          tester,
          activeSection: AppSection.chats,
          cavitySection: AppSection.chats,
          cavityChild: const Text('Chat list'),
          cavityKey: 'chats',
          maxHeightFraction: 0.75,
        );
        expect(cavityHeightOf(tester), greaterThan(0.0));

        // Drag the handle all the way down: the sheet dismisses to 0px (no
        // handle left to grab) — a dismissal, not a height preference.
        await tester.drag(handleFinder(), const Offset(0, 700));
        await tester.pumpAndSettle();
        expect(cavityHeightOf(tester), 0.0);

        // The rail item must reopen it at a usable height, NOT the
        // remembered zero (the #7510 stuck state).
        await tester.tap(find.byTooltip('All chats'));
        await tester.pumpAndSettle();
        expect(
          cavityHeightOf(tester),
          greaterThan(100.0),
          reason: 'reopening after a drag-to-zero must restore a real height',
        );
      },
    );
  });

  group('the toggle keys on what the cavity hosts (#7537)', () {
    testWidgets(
      'Courses tap NAVIGATES to the hub while a course sheet is hosted, '
      'even though the highlight resolves to Courses',
      (tester) async {
        AppSection? tapped;
        await pumpNav(
          tester,
          // A selected course: highlight says Courses, but the cavity hosts
          // the COURSE sheet (cavitySection null), not the hub.
          activeSection: AppSection.courses,
          cavitySection: null,
          cavityChild: const Text('Course sheet'),
          cavityKey: 'course-a',
          cavityDefaultsToPeek: true,
          onSectionTap: (s) => tapped = s,
        );
        final before = cavityHeightOf(tester);

        await tester.tap(find.byTooltip('Courses'));
        await tester.pumpAndSettle();

        expect(
          tapped,
          AppSection.courses,
          reason: 'the tap must navigate to the hub, not toggle the sheet',
        );
        expect(cavityHeightOf(tester), closeTo(before, 1.0));
      },
    );

    testWidgets('Courses tap toggles when the cavity hosts the hub itself', (
      tester,
    ) async {
      AppSection? tapped;
      await pumpNav(
        tester,
        activeSection: AppSection.courses,
        cavitySection: AppSection.courses,
        cavityChild: const Text('Courses hub'),
        cavityKey: 'addcourse',
        onSectionTap: (s) => tapped = s,
      );
      expect(cavityHeightOf(tester), greaterThan(0.0));

      await tester.tap(find.byTooltip('Courses'));
      await tester.pumpAndSettle();

      expect(tapped, isNull, reason: 'the active hub tap is a toggle');
      expect(cavityHeightOf(tester), 0.0);
    });

    testWidgets('the course shortcut toggles its own hosted sheet instead of a '
        'same-URL no-op', (tester) async {
      var shortcutTaps = 0;
      await pumpNav(
        tester,
        activeSection: AppSection.courses,
        cavitySection: null,
        courseShortcutHostsCavity: true,
        cavityChild: const Text('Course sheet'),
        cavityKey: 'course-a',
        cavityDefaultsToPeek: true,
        onCourseShortcutTap: () => shortcutTaps++,
      );
      final peek = cavityHeightOf(tester);
      expect(peek, greaterThan(0.0));

      // Expanded -> tap collapses (ephemeral), no navigation.
      await tester.tap(find.byTooltip('Add a course'));
      await tester.pumpAndSettle();
      expect(shortcutTaps, 0);
      expect(cavityHeightOf(tester), 0.0);

      // Collapsed -> tap re-expands to the remembered height.
      await tester.tap(find.byTooltip('Add a course'));
      await tester.pumpAndSettle();
      expect(shortcutTaps, 0);
      expect(cavityHeightOf(tester), closeTo(peek, 1.0));
    });

    testWidgets(
      'the course shortcut navigates when its course is NOT the hosted sheet',
      (tester) async {
        var shortcutTaps = 0;
        await pumpNav(
          tester,
          activeSection: AppSection.chats,
          cavitySection: AppSection.chats,
          cavityChild: const Text('Chat list'),
          cavityKey: 'chats',
          onCourseShortcutTap: () => shortcutTaps++,
        );

        await tester.tap(find.byTooltip('Add a course'));
        await tester.pumpAndSettle();
        expect(shortcutTaps, 1);
      },
    );
  });

  group('tap-outside collapse', () {
    testWidgets(
      'tapping outside collapses (ephemeral — no navigation), and the rail '
      'item re-expands to the remembered height',
      (tester) async {
        await pumpNav(
          tester,
          activeSection: AppSection.chats,
          cavitySection: AppSection.chats,
          cavityChild: const Text('Chat list'),
          cavityKey: 'chats',
          maxHeightFraction: 0.75,
        );

        final maxHeightPx = 800.0 * 0.75;
        // Expand to full first so the collapse is unambiguous.
        await tester.tap(handleFinder());
        await tester.pumpAndSettle();
        expect(cavityHeightOf(tester), closeTo(maxHeightPx, 1.0));

        // Tap far above the floating widget — outside its bounds. The widget
        // mounts Positioned.fill so its barrier spans the whole screen.
        await tester.tapAt(const Offset(200, 20));
        await tester.pumpAndSettle();

        expect(cavityHeightOf(tester), 0.0);
        expect(
          find.text('Chat list'),
          findsNothing,
          reason: 'collapsed hides the cavity content but closes nothing',
        );

        // Tapping the still-active rail item re-expands to the remembered
        // (full) height rather than the section default (half).
        await tester.tap(find.byTooltip('All chats'));
        await tester.pumpAndSettle();
        expect(cavityHeightOf(tester), closeTo(maxHeightPx, 1.0));
      },
    );

    testWidgets('tapping the active rail item while expanded collapses it', (
      tester,
    ) async {
      await pumpNav(
        tester,
        activeSection: AppSection.chats,
        cavitySection: AppSection.chats,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
      );

      expect(cavityHeightOf(tester), greaterThan(0.0));

      await tester.tap(find.byTooltip('All chats'));
      await tester.pumpAndSettle();

      expect(cavityHeightOf(tester), 0.0);
    });
  });

  group('dismiss-on-close sheets (#7614)', () {
    testWidgets('tapping outside a dismiss-on-close sheet calls onDismissed '
        'instead of collapsing', (tester) async {
      var dismissed = 0;
      await pumpNav(
        tester,
        cavityChild: const Text('Activity plan'),
        cavityKey: 'activity-a',
        onDismissed: () => dismissed++,
      );
      expect(cavityHeightOf(tester), greaterThan(0.0));

      // Outside the floating widget — on narrow this is the map.
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();

      expect(dismissed, 1);
    });

    testWidgets('dragging a dismiss-on-close sheet fully down calls '
        'onDismissed', (tester) async {
      var dismissed = 0;
      await pumpNav(
        tester,
        cavityChild: const Text('Activity plan'),
        cavityKey: 'activity-a',
        onDismissed: () => dismissed++,
      );
      expect(cavityHeightOf(tester), greaterThan(0.0));

      await tester.drag(handleFinder(), const Offset(0, 700));
      await tester.pumpAndSettle();

      expect(dismissed, 1);
    });

    testWidgets('without onDismissed the same gestures stay ephemeral '
        'collapses', (tester) async {
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
      );
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(cavityHeightOf(tester), 0.0);
    });
  });

  group('no cavity chrome of its own', () {
    testWidgets('the cavity renders only the handle — no header or X', (
      tester,
    ) async {
      // Every hosted surface brings its own header and close/back affordance
      // (the chat list's panel header, the course card, the activity plan's
      // contextual controls) — a cavity-level X would double them (live QA).
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
      );

      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('Chat list'), findsOneWidget);
    });
  });

  group('height memory', () {
    testWidgets('survives dispose/remount per key', (tester) async {
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
      );

      final maxHeightPx = 800.0 * 0.75;
      await tester.tap(handleFinder()); // half -> full
      await tester.pumpAndSettle();
      expect(cavityHeightOf(tester), closeTo(maxHeightPx, 1.0));

      await unmountNav(tester); // a full-screen surface mounts over it
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
      );

      expect(
        cavityHeightOf(tester),
        closeTo(maxHeightPx, 1.0),
        reason: 'the same key reopens at the height it was left at',
      );
    });

    testWidgets('does not leak across keys', (tester) async {
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
      );
      await tester.tap(handleFinder()); // half -> full
      await tester.pumpAndSettle();

      await unmountNav(tester);
      await pumpNav(
        tester,
        activeSection: AppSection.courses,
        cavityChild: const Text('Course card'),
        cavityKey: 'course-a',
        cavityDefaultsToPeek: true,
        maxHeightFraction: 0.75,
      );

      final maxHeightPx = 800.0 * 0.75;
      final height = cavityHeightOf(tester);
      expect(
        height,
        closeTo(128.0, 1.0), // the course peek, NOT the chats key's full
        reason: 'a different key must not inherit the previous key\'s height',
      );
      expect(height, lessThan(maxHeightPx));
    });
  });
}
