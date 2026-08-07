import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/invited_course_badge.dart';
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
    String? cavityContextId,
    bool cavityDefaultsToPeek = false,
    void Function(AppSection section)? onSectionTap,
    VoidCallback? onCourseShortcutTap,
    double maxHeightFraction = 0.75,
    double? preferredCavityHeightPx,
    AppSection? cavitySection,
    bool courseShortcutHostsCavity = false,
    VoidCallback? onDismissed,
    ValueChanged<bool>? onCavityFullChanged,
    double keyboardInset = 0.0,
    Widget Function(Widget child)? chatsBadgeBuilder,
    ValueListenable<bool>? courseInvitePending,
    bool settle = true,
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
            cavityContextId: cavityContextId,
            cavityDefaultsToPeek: cavityDefaultsToPeek,
            maxHeightFraction: maxHeightFraction,
            preferredCavityHeightPx: preferredCavityHeightPx,
            cavitySection: cavitySection,
            courseShortcutHostsCavity: courseShortcutHostsCavity,
            onDismissed: onDismissed,
            onCavityFullChanged: onCavityFullChanged,
            keyboardInset: keyboardInset,
            chatsBadgeBuilder: chatsBadgeBuilder,
            courseInvitePending: courseInvitePending,
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
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

  // The cavity's rendered height = its animated rest height minus the (instant)
  // keyboard trim. It lives on the SizedBox keyed 'navCavityBox' inside the
  // cavity's TweenAnimationBuilder; absent (0) when there is no cavity.
  double cavityHeightOf(WidgetTester tester) {
    final finder = find.byKey(const ValueKey('navCavityBox'));
    if (finder.evaluate().isEmpty) return 0.0;
    return tester.getSize(finder).height;
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

    testWidgets(
      'the injected badge wraps the Chats item — and only the Chats item '
      '(#8129)',
      (tester) async {
        // The shell injects the all-chats unread badge (UnreadRoomsBadge over
        // its sync stream) through this seam so the widget itself stays free
        // of Matrix lookups. The contract here: whatever is injected must
        // enclose exactly the Chats rail button.
        const badgeKey = ValueKey('chatsUnreadBadge');
        await pumpNav(
          tester,
          chatsBadgeBuilder: (child) =>
              KeyedSubtree(key: badgeKey, child: child),
        );

        expect(
          find.descendant(
            of: find.byKey(badgeKey),
            matching: find.byTooltip('All chats'),
          ),
          findsOneWidget,
          reason: 'the badge must enclose the Chats rail item',
        );
        for (final other in ['World', 'Courses', 'Add a course']) {
          expect(
            find.descendant(
              of: find.byKey(badgeKey),
              matching: find.byTooltip(other),
            ),
            findsNothing,
            reason: 'only the Chats item carries the unread badge',
          );
        }
      },
    );

    testWidgets('a badged Chats item still taps through to onSectionTap', (
      tester,
    ) async {
      final tapped = <AppSection>[];
      await pumpNav(
        tester,
        onSectionTap: tapped.add,
        // A wrapper that adds real chrome around the button, like the badge
        // Stack does — the tap must reach the button through it.
        chatsBadgeBuilder: (child) =>
            Padding(padding: const EdgeInsets.all(2.0), child: child),
      );

      await tester.tap(find.byTooltip('All chats'));
      await tester.pumpAndSettle();

      expect(tapped, [AppSection.chats]);
    });

    // The badge is mounted at zero opacity when no invite is pending (the
    // badges package's own appear/disappear animation), so "is it showing" is
    // a question about the semantics tree, not about the widget tree. Matched
    // loosely because the rail row merges the badge's label into its own node.
    Finder shownInviteBadge() => find.bySemanticsLabel(RegExp('Invited'));

    testWidgets(
      'a pending course invite badges the Courses item — and only the '
      'Courses item (#8190)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpNav(tester, courseInvitePending: ValueNotifier(true));

        expect(shownInviteBadge(), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(InvitedCourseBadge),
            matching: find.byTooltip('Courses'),
          ),
          findsOneWidget,
          reason: 'the badge must enclose the Courses rail item',
        );
        for (final other in ['World', 'All chats', 'Add a course']) {
          expect(
            find.descendant(
              of: find.byType(InvitedCourseBadge),
              matching: find.byTooltip(other),
            ),
            findsNothing,
            reason: 'only the Courses item carries the invite badge',
          );
        }
        semantics.dispose();
      },
    );

    testWidgets('no pending invite leaves the Courses item bare', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpNav(tester, courseInvitePending: ValueNotifier(false));
      expect(shownInviteBadge(), findsNothing);

      // And a shell that passes nothing at all is the same as no invite.
      await unmountNav(tester);
      await pumpNav(tester);
      expect(shownInviteBadge(), findsNothing);
      semantics.dispose();
    });

    testWidgets('the badge follows the invite arriving and being resolved', (
      tester,
    ) async {
      // The whole reason this is a listenable: sync flips it under a nav
      // widget that is otherwise not rebuilding.
      final semantics = tester.ensureSemantics();
      final pending = ValueNotifier(false);
      addTearDown(pending.dispose);
      await pumpNav(tester, courseInvitePending: pending);
      expect(shownInviteBadge(), findsNothing);

      pending.value = true;
      await tester.pumpAndSettle();
      expect(shownInviteBadge(), findsOneWidget);

      pending.value = false;
      await tester.pumpAndSettle();
      expect(shownInviteBadge(), findsNothing);
      semantics.dispose();
    });

    testWidgets('a badged Courses item still taps through to onSectionTap', (
      tester,
    ) async {
      final tapped = <AppSection>[];
      await pumpNav(
        tester,
        onSectionTap: tapped.add,
        courseInvitePending: ValueNotifier(true),
      );

      await tester.tap(find.byTooltip('Courses'));
      await tester.pumpAndSettle();

      expect(tapped, [AppSection.courses]);
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
      'a course covered by a chat and reopened restores its height (#7332)',
      (tester) async {
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityContextId: 'course-a',
          cavityDefaultsToPeek: true,
        );
        final peek = cavityHeightOf(tester);

        // Expand to full (tap-the-body, #7609).
        await tester.tap(find.text('Course card'));
        await tester.pumpAndSettle();
        final expanded = cavityHeightOf(tester);
        expect(expanded, greaterThan(peek));

        // A chat opening over the course DISPOSES the nav widget (the shell
        // drops it under a full-screen focus); closing the chat mounts it fresh.
        // The course context (`?c=`) never left — the course was only covered —
        // so it must reopen at the height the learner left it, not peek (#7332).
        await unmountNav(tester);
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityContextId: 'course-a',
          cavityDefaultsToPeek: true,
        );
        expect(cavityHeightOf(tester), closeTo(expanded, 1.0));
      },
    );

    testWidgets(
      'a course keeps its height across opening and closing an activity (#7332)',
      (tester) async {
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityContextId: 'course-a',
          cavityDefaultsToPeek: true,
        );
        final peek = cavityHeightOf(tester);

        await tester.tap(find.text('Course card'));
        await tester.pumpAndSettle();
        final expanded = cavityHeightOf(tester);
        expect(expanded, greaterThan(peek));

        // Open an activity from the course: it rides the SAME cavity (the key
        // swaps course->activity) but keeps the course context, so it must NOT
        // forget the course's height. Then close the activity back to the card.
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Activity plan'),
          cavityKey: 'activity-x',
          cavityContextId: 'course-a',
        );
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityContextId: 'course-a',
          cavityDefaultsToPeek: true,
        );
        expect(cavityHeightOf(tester), closeTo(expanded, 1.0));
      },
    );

    testWidgets(
      'a course genuinely closed reopens at peek, not its last height (#7609)',
      (tester) async {
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityContextId: 'course-a',
          cavityDefaultsToPeek: true,
        );
        final peek = cavityHeightOf(tester);

        // Expand to full, then LEAVE the course context — World clears `?c=`
        // (the only thing besides picking another course that resets scope).
        // That, unlike a covering chat or an in-course activity, forgets the
        // height (#7609).
        await tester.tap(find.text('Course card'));
        await tester.pumpAndSettle();
        expect(cavityHeightOf(tester), greaterThan(peek));
        await pumpNav(tester, activeSection: AppSection.world);

        // Reopening the same course arrives at the default peek — the
        // deterministic entry state; the expanded height was forgotten on close.
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityContextId: 'course-a',
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

    testWidgets(
      'the handle is its own tappable semantics node, not merged into the '
      'scrollable cavity (#7927)',
      (tester) async {
        // The activity-plan cavity (non-peek, dismiss-on-close): its outer
        // cavity GestureDetector carries the vertical-drag (scroll) actions but
        // no tap of its own. The handle must still surface as its OWN button
        // node. If it merges into the scrollable cavity node — inheriting
        // scrollUp/scrollDown — Flutter web's accessibility layer stops
        // delivering the tap, so clicking the handle does nothing and the sheet
        // can only be dragged (the #7927 report: reproduced on Opera/Windows,
        // where the a11y layer is active, but not on Chrome, where it isn't).
        final semantics = tester.ensureSemantics();
        await pumpNav(
          tester,
          cavityChild: const Text('Activity plan'),
          cavityKey: 'activity-a',
          onDismissed: () {},
        );

        final l10n = L10n.of(tester.element(find.byType(MobileNavWidget)));

        // Walk to the semantics root from any node, then collect every node
        // carrying the handle label.
        SemanticsNode root = tester.getSemantics(find.byType(MobileNavWidget));
        while (root.parent != null) {
          root = root.parent!;
        }

        final labelled = <SemanticsData>[];
        void collect(SemanticsNode node) {
          final data = node.getSemanticsData();
          if (data.label.contains(l10n.resizeCoursePanel)) labelled.add(data);
          node.visitChildren((child) {
            collect(child);
            return true;
          });
        }

        collect(root);

        expect(
          labelled,
          hasLength(1),
          reason: 'the handle must surface as exactly one semantics node',
        );
        final handle = labelled.single;

        expect(
          handle.hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'the handle node must run the resize toggle on tap',
        );
        // The crux of #7927: a handle merged into the scrollable cavity node
        // would inherit its scroll actions (and the hosted content's label),
        // and that scrollable+tappable node drops the tap on Flutter web.
        expect(
          handle.hasAction(SemanticsAction.scrollUp),
          isFalse,
          reason: 'the handle must be its own node, not the scrollable cavity',
        );
        expect(handle.hasAction(SemanticsAction.scrollDown), isFalse);
        expect(
          handle.label,
          l10n.resizeCoursePanel,
          reason: 'a merged node would also carry the cavity content label',
        );

        semantics.dispose();
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
      'the `+` shortcut toggles the add-course hub it is showing (#8098)',
      (tester) async {
        // With no courses joined the 4th slot IS the `+` add-course button, so
        // the hub is its own surface and the Courses item beside it toggles the
        // very same cavity. Distinct from the course-sheet case above: a
        // SECTION cavity is not a peek, so the collapse renders 0px and the
        // re-expand comes from the remembered content-fit height, not a peek.
        var shortcutTaps = 0;
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavitySection: AppSection.courses,
          courseShortcutHostsCavity: true,
          cavityChild: const Text('Courses hub'),
          cavityKey: 'addcourse',
          onCourseShortcutTap: () => shortcutTaps++,
        );
        final open = cavityHeightOf(tester);
        expect(open, greaterThan(0.0));

        await tester.tap(find.byTooltip('Add a course'));
        await tester.pumpAndSettle();
        expect(shortcutTaps, 0, reason: 'the active hub tap is a toggle');
        expect(cavityHeightOf(tester), 0.0);

        await tester.tap(find.byTooltip('Add a course'));
        await tester.pumpAndSettle();
        expect(shortcutTaps, 0);
        expect(cavityHeightOf(tester), closeTo(open, 1.0));
      },
    );

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

  group('course shortcut is its own semantics node (#7944)', () {
    testWidgets(
      'the course shortcut surfaces as a standalone tappable node, not merged '
      'into the rail container',
      (tester) async {
        // The other three rail items are IconButtons, which stand alone. The
        // course shortcut is a custom InkWell; without `container: true` its
        // tap + selected state merged UP into the rail's "Navigation options"
        // node, leaving it with no node of its own. On Flutter web with the
        // accessibility layer active (Firefox / release builds), a tap on that
        // merged rail node dispatched to the live map behind and fell through —
        // so a collapsed course could never be re-expanded by the shortcut
        // (#7944; the sibling web-semantics tap loss of #7927 / #7803). Forcing
        // the shortcut into its own container node fixes it.
        final semantics = tester.ensureSemantics();
        await pumpNav(
          tester,
          activeSection: AppSection.courses,
          cavitySection: null,
          courseShortcutHostsCavity: true,
          cavityChild: const Text('Course card'),
          cavityKey: 'course-a',
          cavityDefaultsToPeek: true,
        );

        final l10n = L10n.of(tester.element(find.byType(MobileNavWidget)));

        SemanticsNode root = tester.getSemantics(find.byType(MobileNavWidget));
        while (root.parent != null) {
          root = root.parent!;
        }

        SemanticsData? shortcut;
        SemanticsData? railContainer;
        void collect(SemanticsNode node) {
          final data = node.getSemanticsData();
          if (data.label == 'Add a course') shortcut = data;
          if (data.label == l10n.navOptionsLabel) railContainer = data;
          node.visitChildren((child) {
            collect(child);
            return true;
          });
        }

        collect(root);

        expect(
          shortcut,
          isNotNull,
          reason:
              'the course shortcut must surface as its own labelled node, not '
              'be absorbed into the rail container',
        );
        expect(
          shortcut!.hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'the standalone shortcut node must carry its own tap action',
        );

        // The crux of #7944: the rail container must NOT carry the shortcut's
        // tap — a merged tap on the wide rail node is what Firefox dropped to
        // the map.
        expect(
          railContainer,
          isNotNull,
          reason: 'the rail container node should still exist',
        );
        expect(
          railContainer!.hasAction(SemanticsAction.tap),
          isFalse,
          reason: 'the rail container must not absorb the shortcut tap',
        );

        semantics.dispose();
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

  group('keyboard inset (#7754)', () {
    // The cavity shrinks by the keyboard height so its top (and the search
    // field above it) stays clear of the analytics bar (#7754).
    testWidgets('shrinks the cavity by the keyboard height', (tester) async {
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
      );
      final maxHeightPx = 800.0 * 0.75;
      // Baseline: opens at half with no keyboard.
      expect(cavityHeightOf(tester), closeTo(maxHeightPx * 0.5, 1.0));

      // Remount with a 200px keyboard up: the half-height cavity is trimmed
      // by exactly that inset.
      await unmountNav(tester);
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
        keyboardInset: 200.0,
      );
      expect(cavityHeightOf(tester), closeTo(maxHeightPx * 0.5 - 200.0, 1.0));
    });

    testWidgets('a keyboard taller than the cavity clamps to zero, not '
        'negative', (tester) async {
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
        // Half height is 300px; a 500px inset would drive it negative.
        keyboardInset: 500.0,
      );
      expect(cavityHeightOf(tester), 0.0);
    });
  });

  group('keyboard over a focused cavity input (#8072)', () {
    // A course card rests at peek and the add-course steps at a short half —
    // both shorter than the software keyboard. Tapping an input inside one used
    // to trim the cavity to nothing, which unmounted the field, dropped its
    // focus and closed the keyboard again. It must instead grow to full.
    const field = TextField(decoration: InputDecoration(hintText: 'Code'));

    Future<void> pumpCourseCavity(
      WidgetTester tester, {
      double keyboardInset = 0.0,
      bool settle = true,
    }) => pumpNav(
      tester,
      cavityChild: field,
      cavityKey: 'course-a',
      cavityContextId: 'course-a',
      cavityDefaultsToPeek: true,
      maxHeightFraction: 0.75,
      keyboardInset: keyboardInset,
      settle: settle,
    );

    bool inputHasFocus(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode
        .hasFocus;

    testWidgets('grows a peeking cavity to full so the input stays visible', (
      tester,
    ) async {
      await pumpCourseCavity(tester);
      expect(cavityHeightOf(tester), closeTo(128.0, 1.0));

      // Tap the field, then let the keyboard the tap summoned arrive.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await pumpCourseCavity(tester, keyboardInset: 300.0);

      final maxHeightPx = 800.0 * 0.75;
      expect(
        cavityHeightOf(tester),
        closeTo(maxHeightPx - 300.0, 1.0),
        reason: 'full height, minus the keyboard trim of #7754',
      );
      expect(
        inputHasFocus(tester),
        isTrue,
        reason: 'the field the learner tapped keeps its focus',
      );
    });

    testWidgets('keeps the focused input mounted while the cavity grows', (
      tester,
    ) async {
      await pumpCourseCavity(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // A keyboard taller than the peek, observed on the FIRST frame — before
      // the grow has animated anywhere. Without the focused floor the cavity is
      // 0px here and the field is gone from the tree.
      await pumpCourseCavity(tester, keyboardInset: 500.0, settle: false);
      expect(cavityHeightOf(tester), greaterThan(0.0));
      expect(find.byType(TextField), findsOneWidget);
      expect(inputHasFocus(tester), isTrue);

      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(inputHasFocus(tester), isTrue);
    });

    testWidgets('does not remember the keyboard height for the next open', (
      tester,
    ) async {
      await pumpCourseCavity(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await pumpCourseCavity(tester, keyboardInset: 300.0);

      // The course reopens at the height the LEARNER left it at — the peek —
      // not the full the keyboard forced (#7332, #7609).
      await unmountNav(tester);
      await pumpCourseCavity(tester);
      expect(cavityHeightOf(tester), closeTo(128.0, 1.0));
    });

    testWidgets('leaves an unfocused cavity to the plain #7754 trim', (
      tester,
    ) async {
      // The search bar riding ABOVE the widget owns this keyboard; nothing in
      // the cavity is focused, so the cavity neither grows nor holds a floor.
      await pumpCourseCavity(tester, keyboardInset: 300.0);
      expect(cavityHeightOf(tester), 0.0);
    });
  });

  group('full-height reporting (#7697)', () {
    testWidgets('reports full only on settle, and toggles back on collapse', (
      tester,
    ) async {
      final reports = <bool>[];
      await pumpNav(
        tester,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
        onCavityFullChanged: reports.add,
      );
      // Opens at half — never full — so nothing is reported yet.
      expect(reports, isEmpty);

      // Handle tap settles at full: one true report.
      await tester.tap(handleFinder());
      await tester.pumpAndSettle();
      expect(reports, [true]);

      // Handle tap settles back at half: reports false. Only real changes fire.
      await tester.tap(handleFinder());
      await tester.pumpAndSettle();
      expect(reports, [true, false]);
    });

    testWidgets('an ephemeral tap-outside collapse reports not-full', (
      tester,
    ) async {
      final reports = <bool>[];
      await pumpNav(
        tester,
        activeSection: AppSection.chats,
        cavitySection: AppSection.chats,
        cavityChild: const Text('Chat list'),
        cavityKey: 'chats',
        maxHeightFraction: 0.75,
        onCavityFullChanged: reports.add,
      );
      await tester.tap(handleFinder()); // -> full
      await tester.pumpAndSettle();
      expect(reports, [true]);

      // Tap outside collapses ephemerally — the sheet is no longer full.
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(reports, [true, false]);
    });
  });
}
