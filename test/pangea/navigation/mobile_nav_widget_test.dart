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
      // A small peek: clearly above 0 (rail-only) but well short of half.
      expect(height, greaterThan(0.0));
      expect(height, lessThan(maxHeightPx * 0.4));
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
  });

  group('tap-outside collapse', () {
    testWidgets(
      'tapping outside collapses (ephemeral — no navigation), and the rail '
      'item re-expands to the remembered height',
      (tester) async {
        await pumpNav(
          tester,
          activeSection: AppSection.chats,
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
        lessThan(maxHeightPx * 0.4),
        reason: 'a different key must not inherit the previous key\'s height',
      );
    });
  });
}
