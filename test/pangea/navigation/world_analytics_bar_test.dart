import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/analytics_header_avatar.dart';
import 'package:fluffychat/routes/world/circular_xp_ring_painter.dart';
import 'package:fluffychat/routes/world/hex_level_badge.dart';
import 'package:fluffychat/routes/world/level_up_badge_celebration.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model.dart';
import 'package:fluffychat/routes/world/world_analytics_bar.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/routes/world/xp_border_painter.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'mock_user_cluster_view_model.dart';

/// Coverage for the world_v2 single-column analytics NAV BAR
/// (routing.instructions.md, "Single-column analytics nav bar").
/// [WorldAnalyticsBar] / [AnalyticsHeaderAvatar] read live Matrix/analytics
/// streams (mirroring `WorldUserCluster`'s data sourcing), which have no
/// lightweight test double here, so this file drives their plain-values
/// renderings — [WorldAnalyticsBar] (the full bar) and [AnalyticsHeaderAvatarInternal]
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
    required UserClusterViewModel viewModel,
    ProgressIndicatorEnum? selectedTab,
  }) => pumpShellMounted(
    tester,
    WorldAnalyticsBarInternal(
      flagBuilder: flagStandIn,
      viewModel: viewModel,
      selectedTab: selectedTab,
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
      await pumpBar(tester, viewModel: MockUserClusterViewModel());
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
        await pumpBar(tester, viewModel: MockUserClusterViewModel());
        final size = tester.getSize(find.byType(WorldAnalyticsBarInternal));
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
      final viewModel = MockUserClusterViewModel();

      await pumpBar(tester, viewModel: viewModel);
      final l10n = l10nOf(tester);

      await tester.tap(find.bySemanticsLabel('${l10n.vocab}: 0'));
      expect(viewModel.tappedTab, AnalyticsPanelTab.vocab);

      await tester.tap(find.bySemanticsLabel(l10n.settings));
      expect(viewModel.avatarTaps, 1);

      await tester.tap(find.bySemanticsLabel('${l10n.level} 1'));
      expect(viewModel.levelTaps, 1);

      await tester.tap(
        find.bySemanticsLabel(
          '${es.getDisplayName(l10n)}, ${l10n.learningSettings}',
        ),
      );
      expect(viewModel.flagTaps, 1);

      semantics.dispose();
    });

    testWidgets('a level-up event pops the celebration chip at the hex badge', (
      tester,
    ) async {
      // The bar view threads the level-change signal (the one the old
      // top-down snackbar consumed, #7432) into the badge's
      // LevelUpBadgeCelebration.
      final controller = StreamController<LevelUpdate>.broadcast();
      final viewModel = MockUserClusterViewModel(
        levelUpdates: controller.stream,
      );
      await pumpBar(tester, viewModel: viewModel);
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

    testWidgets('the chip stays on-screen on a narrow phone (#8257)', (
      tester,
    ) async {
      // The bug: the badge overhangs the pill's left end near the screen's
      // edge, so a chip hanging off its LEADING edge was mostly cut off. The
      // bar passes `chipBelow`, which drops it under the badge instead.
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = StreamController<LevelUpdate>.broadcast();
      final viewModel = MockUserClusterViewModel(
        levelUpdates: controller.stream,
      );
      await pumpBar(tester, viewModel: viewModel);
      final chipText = l10nOf(tester).levelUpChip(2);

      controller.add(const LevelUpdate(prevLevel: 1, newLevel: 2));
      await tester.pump();
      await tester.pump();

      final badge = tester.getRect(find.byType(HexLevelBadge));
      final chip = tester.getRect(find.text(chipText));
      expect(chip.top, greaterThanOrEqualTo(badge.bottom));
      expect(chip.left, greaterThanOrEqualTo(0.0));
      expect(chip.right, lessThanOrEqualTo(375.0));

      await tester.pump(LevelUpBadgeCelebration.defaultPulseDuration);
      await tester.pump(
        LevelUpBadgeCelebration.defaultChipDuration +
            const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      await controller.close();
    });
  });

  /// The open-panel highlight: the bar is the single-column rendering of the
  /// web cluster, so whichever analytics page is open is lit here too — all
  /// four controls, the level badge included (#7977, #8062).
  group('full bar — open-panel highlight', () {
    /// The trackers' sticky wash: the only decorated [Ink] in the bar.
    final trackerHighlights = find.byWidgetPredicate(
      (w) => w is Ink && w.decoration != null,
    );

    Finder trackerHighlight(ProgressIndicatorEnum indicator) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is ClusterTrackerButton && w.indicator == indicator,
      ),
      matching: trackerHighlights,
    );

    /// The badge's lit state is its own gold, not a wash behind or around it
    /// (#8067) — so read the color it is actually painted with.
    Color badgeFill(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(HexLevelBadge),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as HexBadgePainter)
            .fill;

    /// No decorated box may wrap the badge: the circular wash #8067 removed.
    final levelWash = find.ancestor(
      of: find.byType(HexLevelBadge),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration != null,
      ),
    );

    testWidgets('nothing is lit while no analytics panel is open', (
      tester,
    ) async {
      await pumpBar(tester, viewModel: MockUserClusterViewModel());

      expect(trackerHighlights, findsNothing);
      expect(
        badgeFill(tester),
        AppConfig.goldByTheme(tester.element(find.byType(Scaffold))),
      );
    });

    for (final (tab, name) in [
      (ProgressIndicatorEnum.stars, 'stars'),
      (ProgressIndicatorEnum.morphsUsed, 'grammar'),
      (ProgressIndicatorEnum.wordsUsed, 'vocab'),
    ]) {
      testWidgets('the $name tracker alone is lit for its open panel', (
        tester,
      ) async {
        await pumpBar(
          tester,
          viewModel: MockUserClusterViewModel(),
          selectedTab: tab,
        );

        expect(trackerHighlight(tab), findsOneWidget);
        // Exactly one control wears the wash — no sibling tracker, and the
        // badge keeps its default gold.
        expect(trackerHighlights, findsOneWidget);
        expect(
          badgeFill(tester),
          AppConfig.goldByTheme(tester.element(find.byType(Scaffold))),
        );
      });
    }

    testWidgets('the level badge alone is lit for the open Level page', (
      tester,
    ) async {
      await pumpBar(
        tester,
        viewModel: MockUserClusterViewModel(),
        selectedTab: ProgressIndicatorEnum.level,
      );

      expect(trackerHighlights, findsNothing);
      // The badge's own gold deepens — no wash of any kind around it (#8067).
      expect(
        badgeFill(tester),
        AppConfig.goldHighlightByTheme(tester.element(find.byType(Scaffold))),
      );
      expect(levelWash, findsNothing);
    });

    testWidgets('lighting the badge moves nothing', (tester) async {
      // Lighting is a pure color change, so opening the Level page must not
      // shove the badge (or the pill it overhangs) sideways.
      await pumpBar(tester, viewModel: MockUserClusterViewModel());
      final unlit = tester.getRect(find.byType(HexLevelBadge));

      await pumpBar(
        tester,
        viewModel: MockUserClusterViewModel(),
        selectedTab: ProgressIndicatorEnum.level,
      );
      expect(tester.getRect(find.byType(HexLevelBadge)), unlit);
    });

    testWidgets('hovering the badge deepens its gold, without a wash', (
      tester,
    ) async {
      await pumpBar(tester, viewModel: MockUserClusterViewModel());
      final context = tester.element(find.byType(Scaffold));
      expect(badgeFill(tester), AppConfig.goldByTheme(context));

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(HexLevelBadge))),
      );
      await tester.pump();

      expect(badgeFill(tester), AppConfig.goldHighlightByTheme(context));
      expect(levelWash, findsNothing);

      // And it goes back when the pointer leaves.
      await tester.sendEventToBinding(pointer.hover(Offset.zero));
      await tester.pump();
      expect(badgeFill(tester), AppConfig.goldByTheme(context));
    });
  });

  group('chat-header avatar (CollapsedAvatarView)', () {
    Future<void> pumpAvatar(
      WidgetTester tester, {
      required UserClusterViewModel viewModel,
      double scale = 1.0,
    }) => pumpShellMounted(
      tester,
      Align(
        alignment: Alignment.centerRight,
        child: AnalyticsHeaderAvatarInternal(
          viewModel: viewModel,
          scale: scale,
          flagBuilder: flagStandIn,
        ),
      ),
    );

    testWidgets('is one named button; the bar controls are absent', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpAvatar(tester, viewModel: MockUserClusterViewModel());
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
      final viewModel = MockUserClusterViewModel();
      await pumpAvatar(tester, viewModel: viewModel);

      await tester.tap(
        find.bySemanticsLabel(l10nOf(tester).analyticsAndSettingsLabel),
      );
      expect(viewModel.taps, 1);
      // A plain button: nothing expands, nothing is pending.
      await tester.pump(const Duration(seconds: 5));
      expect(find.bySemanticsLabel(l10nOf(tester).settings), findsNothing);

      semantics.dispose();
    });

    testWidgets(
      'a level-up event pops the celebration chip at the mini badge',
      (tester) async {
        final controller = StreamController<LevelUpdate>.broadcast();
        final viewModel = MockUserClusterViewModel(
          levelUpdates: controller.stream,
        );
        await pumpAvatar(tester, scale: 0.75, viewModel: viewModel);
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
      await pumpAvatar(
        tester,
        scale: 0.75,
        viewModel: MockUserClusterViewModel(),
      );
      final box = tester.getSize(find.byType(AnalyticsHeaderAvatarInternal));
      expect(box.height, lessThanOrEqualTo(kToolbarHeight));
    });
  });

  /// The level number and the XP ring must track live XP on every rendering
  /// of the cluster (analytics-system.instructions.md, "Key Contracts": read
  /// `derivedData` inside a StreamBuilder on the construct stream). The
  /// chat-header avatar had no such subscription, so its badge froze at the
  /// mount-time level while the celebration chip announced a later one
  /// (#8437). Each rendering is pinned here so no future one drifts.
  group('live level + XP progress (#8437)', () {
    // 100 XP: past the level-2 floor (38), well short of level 3 (263) — so
    // both the number and the ring visibly move from the level-1 defaults.
    final gained = DerivedAnalyticsDataModel(totalXP: 100);

    Future<void> earnXp(
      WidgetTester tester,
      MockUserClusterViewModel viewModel,
      StreamController<AnalyticsStreamUpdate> constructUpdates,
    ) async {
      // The live service bumps its cached derived data, THEN ticks the stream.
      viewModel.derived = gained;
      constructUpdates.add(
        AnalyticsStreamUpdate(points: 100, totalPoints: 100),
      );
      // Broadcast delivery, the rebuild, and the derived future each take a
      // frame; nothing animates here, so settling is exact.
      await tester.pumpAndSettle();
    }

    double ringProgressOf<P extends CustomPainter>(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is P),
      );
      final painter = paint.painter;
      return switch (painter) {
        XpBorderPainter() => painter.progress,
        CircularXpRingPainter() => painter.progress,
        _ => throw StateError('unexpected painter $painter'),
      };
    }

    testWidgets('chat-header avatar: badge and ring update on an XP tick', (
      tester,
    ) async {
      final constructUpdates =
          StreamController<AnalyticsStreamUpdate>.broadcast();
      addTearDown(constructUpdates.close);
      final viewModel = MockUserClusterViewModel(
        constructUpdateStream: constructUpdates.stream,
      );
      await pumpShellMounted(
        tester,
        Align(
          alignment: Alignment.centerRight,
          child: AnalyticsHeaderAvatarInternal(
            viewModel: viewModel,
            scale: 0.75,
            flagBuilder: flagStandIn,
          ),
        ),
      );
      expect(tester.widget<HexLevelBadge>(find.byType(HexLevelBadge)).level, 1);
      expect(ringProgressOf<CircularXpRingPainter>(tester), 0.0);

      await earnXp(tester, viewModel, constructUpdates);

      expect(tester.widget<HexLevelBadge>(find.byType(HexLevelBadge)).level, 2);
      expect(
        ringProgressOf<CircularXpRingPainter>(tester),
        closeTo(gained.levelProgress, 1e-9),
      );
    });

    testWidgets('full bar: badge and pill ring update on an XP tick', (
      tester,
    ) async {
      final constructUpdates =
          StreamController<AnalyticsStreamUpdate>.broadcast();
      addTearDown(constructUpdates.close);
      final viewModel = MockUserClusterViewModel(
        constructUpdateStream: constructUpdates.stream,
      );
      await pumpBar(tester, viewModel: viewModel);
      expect(tester.widget<HexLevelBadge>(find.byType(HexLevelBadge)).level, 1);
      expect(ringProgressOf<XpBorderPainter>(tester), 0.0);

      await earnXp(tester, viewModel, constructUpdates);

      expect(tester.widget<HexLevelBadge>(find.byType(HexLevelBadge)).level, 2);
      expect(
        ringProgressOf<XpBorderPainter>(tester),
        closeTo(gained.levelProgress, 1e-9),
      );
    });

    testWidgets('web cluster: medal and pill ring update on an XP tick', (
      tester,
    ) async {
      final constructUpdates =
          StreamController<AnalyticsStreamUpdate>.broadcast();
      addTearDown(constructUpdates.close);
      // No L2: the cluster has no offline flag seam, and the real chip loads a
      // network SVG. The level/XP path under test doesn't depend on it.
      final viewModel = MockUserClusterViewModel(
        constructUpdateStream: constructUpdates.stream,
        hasL2: false,
      );
      await pumpShellMounted(
        tester,
        Align(
          alignment: Alignment.topRight,
          child: WorldUserClusterInternal(viewModel: viewModel),
        ),
      );
      expect(
        tester.widget<ClusterLevelMedal>(find.byType(ClusterLevelMedal)).level,
        1,
      );
      expect(ringProgressOf<XpBorderPainter>(tester), 0.0);

      await earnXp(tester, viewModel, constructUpdates);

      expect(
        tester.widget<ClusterLevelMedal>(find.byType(ClusterLevelMedal)).level,
        2,
      );
      expect(
        ringProgressOf<XpBorderPainter>(tester),
        closeTo(gained.levelProgress, 1e-9),
      );
    });
  });
}
