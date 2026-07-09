import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/level_up_badge_celebration.dart';
import 'package:fluffychat/routes/world/world_analytics_bar.dart';

/// Coverage for the world_v2 single-column analytics NAV BAR
/// (routing.instructions.md, "Single-column analytics nav bar").
/// [WorldAnalyticsBar] / [AnalyticsHeaderAvatar] read live Matrix/analytics
/// streams (mirroring `WorldUserCluster`'s data sourcing), which have no
/// lightweight test double here, so this file drives their plain-values
/// renderings — [AnalyticsBarView] (the full bar) and [CollapsedAvatarView]
/// (the chat-header avatar) — directly. The old temporary-expansion state
/// machine (collapsed rendering, ~3s timer, WCAG focus suspension) is gone:
/// full-screen chats host the avatar in their own app bar as a plain button.
void main() {
  final es = LanguageModel(langCode: 'es', displayName: 'Spanish');

  /// The offline flag stand-in: the real chip loads a network SVG whose async
  /// parse throws into the test zone; this carries the same semantics
  /// contract (label + tap).
  Widget flagStandIn(
    LanguageModel language,
    VoidCallback onTap,
    double width,
    double height,
    double fontSize,
  ) => Builder(
    builder: (context) => Semantics(
      button: true,
      label:
          '${language.getDisplayName(L10n.of(context))}, '
          '${L10n.of(context).learningSettings}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Text(language.langCodeShort.toUpperCase()),
        ),
      ),
    ),
  );

  /// Mount like the shell does: Positioned(top/left/right) inside a Stack
  /// hands the bar UNBOUNDED height, so its internal Aligns shrink-wrap to
  /// content. A plain bounded `body:` mount stretches those Aligns to fill
  /// the screen — a constraint regime production never uses (and one that
  /// voids any height measurement).
  Future<void> pumpShellMounted(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [Positioned(top: 0, left: 0, right: 0, child: child)],
          ),
        ),
      ),
    );
    // The L10n delegates load asynchronously, so one pump isn't enough for
    // the home to mount (same as the other mobile-chrome tests).
    await tester.pumpAndSettle();
  }

  Future<void> pumpBar(
    WidgetTester tester, {
    void Function(AnalyticsPanelTab)? onTrackerTap,
    VoidCallback? onAvatarTap,
    VoidCallback? onLevelTap,
    VoidCallback? onFlagTap,
    Stream<LevelUpdate>? levelUpdates,
  }) => pumpShellMounted(
    tester,
    AnalyticsBarView(
      avatarUrl: null,
      displayName: 'Ada',
      l2: es,
      starsCount: 0,
      grammarCount: 0,
      vocabCount: 0,
      level: 1,
      xpProgress: 0.0,
      isInitializing: false,
      levelUpdates: levelUpdates,
      onTrackerTap: onTrackerTap ?? (_) {},
      onAvatarTap: onAvatarTap ?? () {},
      onLevelTap: onLevelTap ?? () {},
      onFlagTap: onFlagTap ?? () {},
      flagBuilder: flagStandIn,
    ),
  );

  setUpAll(() {
    // `Avatar` (inside the bar's atoms) resolves the bot name from the
    // environment at build time; initialize dotenv with an inline value so no
    // real `.env` file is needed (CI has none).
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  L10n l10nOf(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(Scaffold)));

  group('full bar (AnalyticsBarView)', () {
    testWidgets('renders the full bar with all named controls', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpBar(tester);
      final l10n = l10nOf(tester);

      expect(find.bySemanticsLabel(l10n.settings), findsOneWidget);
      expect(find.bySemanticsLabel('${l10n.level} 1'), findsOneWidget);
      expect(find.bySemanticsLabel('${l10n.vocab}: 0'), findsOneWidget);
      expect(find.bySemanticsLabel('${l10n.grammar}: 0'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('.*: 0')),
        findsNWidgets(3), // stars, grammar, vocab trackers
      );
      expect(
        find.bySemanticsLabel(
          '${es.getDisplayName(l10n)}, ${l10n.learningSettings}',
        ),
        findsOneWidget,
      );

      semantics.dispose();
    });

    testWidgets(
      'the rendered height matches the declared expandedHeight contract',
      (tester) async {
        // The shell's analyticsBarAllowance derives from expandedHeight to
        // place right panels and the search bar BELOW the bar — if the bar's
        // implicit layout grows past the declared constant, that content
        // slides back underneath it.
        await pumpBar(tester);
        final size = tester.getSize(find.byType(AnalyticsBarView));
        expect(
          size.height,
          lessThanOrEqualTo(WorldAnalyticsBar.expandedHeight),
        );
      },
    );

    testWidgets('tapping controls fires the expected callbacks', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      AnalyticsPanelTab? tappedTab;
      var avatarTaps = 0;
      var levelTaps = 0;
      var flagTaps = 0;

      await pumpBar(
        tester,
        onTrackerTap: (tab) => tappedTab = tab,
        onAvatarTap: () => avatarTaps++,
        onLevelTap: () => levelTaps++,
        onFlagTap: () => flagTaps++,
      );
      final l10n = l10nOf(tester);

      await tester.tap(find.bySemanticsLabel('${l10n.vocab}: 0'));
      expect(tappedTab, AnalyticsPanelTab.vocab);

      await tester.tap(find.bySemanticsLabel(l10n.settings));
      expect(avatarTaps, 1);

      await tester.tap(find.bySemanticsLabel('${l10n.level} 1'));
      expect(levelTaps, 1);

      await tester.tap(
        find.bySemanticsLabel(
          '${es.getDisplayName(l10n)}, ${l10n.learningSettings}',
        ),
      );
      expect(flagTaps, 1);

      semantics.dispose();
    });

    testWidgets('a level-up event pops the celebration chip at the hex badge', (
      tester,
    ) async {
      // The bar view threads the level-change signal (the one the old
      // top-down snackbar consumed, #7432) into the badge's
      // LevelUpBadgeCelebration.
      final controller = StreamController<LevelUpdate>.broadcast();
      await pumpBar(tester, levelUpdates: controller.stream);
      final chipText = l10nOf(tester).levelUpChip(2);

      expect(find.text(chipText), findsNothing);
      controller.add(const LevelUpdate(prevLevel: 1, newLevel: 2));
      await tester.pump();
      await tester.pump();
      expect(find.text(chipText), findsOneWidget);

      // Run out the celebration's default timings before the test ends.
      await tester.pump(LevelUpBadgeCelebration.defaultPulseDuration);
      await tester.pump(
        LevelUpBadgeCelebration.defaultChipDuration +
            const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(find.text(chipText), findsNothing);
      await controller.close();
    });
  });

  group('chat-header avatar (CollapsedAvatarView)', () {
    Future<void> pumpAvatar(
      WidgetTester tester, {
      required VoidCallback onTap,
      double scale = 1.0,
      Stream<LevelUpdate>? levelUpdates,
    }) => pumpShellMounted(
      tester,
      Align(
        alignment: Alignment.centerRight,
        child: CollapsedAvatarView(
          avatarUrl: null,
          displayName: 'Ada',
          l2: es,
          level: 1,
          xpProgress: 0.0,
          scale: scale,
          onTap: onTap,
          levelUpdates: levelUpdates,
          flagBuilder: flagStandIn,
        ),
      ),
    );

    testWidgets('is one named button; the bar controls are absent', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpAvatar(tester, onTap: () {});
      final l10n = l10nOf(tester);

      expect(
        find.bySemanticsLabel(l10n.analyticsAndSettingsLabel),
        findsOneWidget,
      );
      // The full bar's own controls (trackers, level medal, settings avatar
      // button) are not part of the header avatar — it is a single button.
      expect(find.bySemanticsLabel(l10n.settings), findsNothing);
      expect(find.bySemanticsLabel('${l10n.level} 1'), findsNothing);
      expect(find.bySemanticsLabel('${l10n.vocab}: 0'), findsNothing);

      semantics.dispose();
    });

    testWidgets('tap fires the single callback (no timers, no expansion)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await pumpAvatar(tester, onTap: () => taps++);

      await tester.tap(
        find.bySemanticsLabel(l10nOf(tester).analyticsAndSettingsLabel),
      );
      expect(taps, 1);
      // A plain button: nothing expands, nothing is pending.
      await tester.pump(const Duration(seconds: 5));
      expect(find.bySemanticsLabel(l10nOf(tester).settings), findsNothing);

      semantics.dispose();
    });

    testWidgets(
      'a level-up event pops the celebration chip at the mini badge',
      (tester) async {
        final controller = StreamController<LevelUpdate>.broadcast();
        await pumpAvatar(
          tester,
          onTap: () {},
          scale: 0.75,
          levelUpdates: controller.stream,
        );
        final chipText = l10nOf(tester).levelUpChip(2);

        expect(find.text(chipText), findsNothing);
        controller.add(const LevelUpdate(prevLevel: 1, newLevel: 2));
        await tester.pump();
        await tester.pump();
        expect(find.text(chipText), findsOneWidget);

        await tester.pump(LevelUpBadgeCelebration.defaultPulseDuration);
        await tester.pump(
          LevelUpBadgeCelebration.defaultChipDuration +
              const Duration(milliseconds: 300),
        );
        await tester.pumpAndSettle();
        expect(find.text(chipText), findsNothing);
        await controller.close();
      },
    );

    testWidgets('the app-bar scale keeps the cluster within toolbar height', (
      tester,
    ) async {
      // AnalyticsHeaderAvatar mounts it at 0.75 inside a kToolbarHeight (56)
      // app bar: ring box (44+8)*0.75 = 39, badge overhang 4.5, flag hang
      // 7.5 — the whole cluster must stay comfortably inside the toolbar.
      await pumpAvatar(tester, onTap: () {}, scale: 0.75);
      final box = tester.getSize(find.byType(CollapsedAvatarView));
      expect(box.height, lessThanOrEqualTo(kToolbarHeight));
    });
  });
}
