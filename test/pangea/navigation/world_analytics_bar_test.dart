import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_analytics_bar.dart';

/// Coverage for the world_v2 single-column analytics bar's collapse/expand/
/// timer state machine (routing.instructions.md, "Single-column analytics
/// bar"). [WorldAnalyticsBar] itself reads live Matrix/analytics streams
/// (mirroring `WorldUserCluster`'s data sourcing), which have no lightweight
/// test double here, so this file drives its extracted state machine,
/// [AnalyticsBarTemporaryExpansion], directly with plain values — it owns
/// every behavior under test (collapsed rendering, tap-to-expand, the
/// auto-collapse timer, and the WCAG 2.2.1 focus safeguard) without needing a
/// live Client.
void main() {
  final es = LanguageModel(langCode: 'es', displayName: 'Spanish');

  Future<void> pumpBar(
    WidgetTester tester, {
    required bool collapsed,
    void Function(AnalyticsPanelTab)? onTrackerTap,
    VoidCallback? onAvatarTap,
    VoidCallback? onLevelTap,
    VoidCallback? onFlagTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        // Mount like the shell does: Positioned(top/left/right) inside a
        // Stack hands the bar UNBOUNDED height, so its internal Aligns
        // shrink-wrap to content. A plain bounded `body:` mount stretches
        // those Aligns to fill the screen — a constraint regime production
        // never uses (and one that voids any height measurement).
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnalyticsBarTemporaryExpansion(
                  collapsed: collapsed,
                  avatarUrl: null,
                  displayName: 'Ada',
                  l2: es,
                  starsCount: 0,
                  grammarCount: 0,
                  vocabCount: 0,
                  level: 1,
                  xpProgress: 0.0,
                  isInitializing: false,
                  onTrackerTap: onTrackerTap ?? (_) {},
                  onAvatarTap: onAvatarTap ?? () {},
                  onLevelTap: onLevelTap ?? () {},
                  onFlagTap: onFlagTap ?? () {},
                  // The real flag chip fetches a network SVG whose async parse
                  // throws into the test zone — inject an offline stand-in carrying
                  // the same semantics contract (label + tap) the real chip has.
                  flagBuilder: (language, onTap, width, height, fontSize) =>
                      Builder(
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
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // The L10n delegates load asynchronously, so one pump isn't enough for
    // the home to mount (same as the other mobile-chrome tests). No expansion
    // timer is running yet, so settling here can't eat into a countdown.
    await tester.pumpAndSettle();
  }

  setUpAll(() {
    // `Avatar` (inside the bar's atoms) resolves the bot name from the
    // environment at build time; initialize dotenv with an inline value so no
    // real `.env` file is needed (CI has none).
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  setUp(() {
    // Every test that starts a timer shortens the wait so none of these
    // actually take ~3 real seconds.
    WorldAnalyticsBar.temporaryExpansionDuration = const Duration(
      milliseconds: 50,
    );
  });

  L10n l10nOf(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(Scaffold)));

  group('collapsed', () {
    testWidgets('renders only the avatar-only circle', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpBar(tester, collapsed: true);

      final label = l10nOf(tester).analyticsAndSettingsLabel;
      expect(find.bySemanticsLabel(label), findsOneWidget);
      // None of the expanded bar's own controls (trackers, level medal,
      // settings avatar button) are present while collapsed.
      expect(find.bySemanticsLabel(l10nOf(tester).settings), findsNothing);
      expect(find.bySemanticsLabel('${l10nOf(tester).level} 1'), findsNothing);
      expect(find.bySemanticsLabel('${l10nOf(tester).vocab}: 0'), findsNothing);

      semantics.dispose();
    });

    testWidgets('tap expands the full bar', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpBar(tester, collapsed: true);

      final label = l10nOf(tester).analyticsAndSettingsLabel;
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();

      // The settings avatar button only exists when expanded.
      expect(find.bySemanticsLabel(l10nOf(tester).settings), findsOneWidget);

      semantics.dispose();
    });

    testWidgets(
      'auto-collapses after the (test-shortened) duration with no interaction',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpBar(tester, collapsed: true);
        await tester.tap(
          find.bySemanticsLabel(l10nOf(tester).analyticsAndSettingsLabel),
        );
        await tester.pump();
        expect(find.bySemanticsLabel(l10nOf(tester).settings), findsOneWidget);

        await tester.pump(
          WorldAnalyticsBar.temporaryExpansionDuration +
              const Duration(milliseconds: 10),
        );

        expect(find.bySemanticsLabel(l10nOf(tester).settings), findsNothing);

        semantics.dispose();
      },
    );

    testWidgets(
      'focus inside the bar prevents auto-collapse until focus leaves '
      '(WCAG 2.2.1)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpBar(tester, collapsed: true);
        await tester.tap(
          find.bySemanticsLabel(l10nOf(tester).analyticsAndSettingsLabel),
        );
        await tester.pump();
        expect(find.bySemanticsLabel(l10nOf(tester).settings), findsOneWidget);

        // Give focus to a descendant control the way a keyboard user would —
        // TAB moves primary focus onto the bar's first focusable control (the
        // only focusables in this tree are the bar's own). `Focus.of` on a
        // label's element would resolve to the bar's non-focusable observer
        // scope, silently no-op, and prove nothing.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus,
          isNotNull,
          reason: 'TAB must land focus on a bar control',
        );

        await tester.pump(
          WorldAnalyticsBar.temporaryExpansionDuration +
              const Duration(milliseconds: 10),
        );
        expect(
          find.bySemanticsLabel(l10nOf(tester).settings),
          findsOneWidget,
          reason: 'a timeout must never fire while a descendant holds focus',
        );

        // Focus leaves the bar entirely: the countdown resumes and the bar
        // collapses once it elapses.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pump(
          WorldAnalyticsBar.temporaryExpansionDuration +
              const Duration(milliseconds: 10),
        );

        expect(find.bySemanticsLabel(l10nOf(tester).settings), findsNothing);

        semantics.dispose();
      },
    );

    testWidgets('an interaction inside the bar restarts the timer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var levelTaps = 0;
      await pumpBar(tester, collapsed: true, onLevelTap: () => levelTaps++);
      await tester.tap(
        find.bySemanticsLabel(l10nOf(tester).analyticsAndSettingsLabel),
      );
      await tester.pump();
      expect(find.bySemanticsLabel(l10nOf(tester).settings), findsOneWidget);

      // Wait most of the way to the deadline, then interact — this should
      // restart the countdown from zero rather than letting the original
      // deadline collapse the bar shortly after.
      await tester.pump(
        WorldAnalyticsBar.temporaryExpansionDuration -
            const Duration(milliseconds: 10),
      );
      await tester.tap(find.bySemanticsLabel('${l10nOf(tester).level} 1'));
      expect(levelTaps, 1);
      await tester.pump();

      // The original deadline has now passed, but the bar should still be
      // expanded because the tap restarted the timer.
      await tester.pump(const Duration(milliseconds: 15));
      expect(
        find.bySemanticsLabel(l10nOf(tester).settings),
        findsOneWidget,
        reason: 'an interaction must restart the auto-collapse countdown',
      );

      // The full (fresh) duration after the restart does collapse it.
      await tester.pump(
        WorldAnalyticsBar.temporaryExpansionDuration +
            const Duration(milliseconds: 10),
      );
      expect(find.bySemanticsLabel(l10nOf(tester).settings), findsNothing);

      semantics.dispose();
    });

    testWidgets('collapsed flipping to false resets the temporary state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpBar(tester, collapsed: true);
      await tester.tap(
        find.bySemanticsLabel(l10nOf(tester).analyticsAndSettingsLabel),
      );
      await tester.pump();
      expect(find.bySemanticsLabel(l10nOf(tester).settings), findsOneWidget);

      // The base widget itself became non-collapsed (e.g. the surface is no
      // longer full-screen) — the bar must stay expanded, but the temporary
      // flag and its timer are cleared, not left running underneath.
      await pumpBar(tester, collapsed: false);
      expect(find.bySemanticsLabel(l10nOf(tester).settings), findsOneWidget);

      await tester.pump(
        WorldAnalyticsBar.temporaryExpansionDuration +
            const Duration(milliseconds: 10),
      );
      expect(
        find.bySemanticsLabel(l10nOf(tester).settings),
        findsOneWidget,
        reason:
            'expansion driven by collapsed=false must not be undone by a '
            'stale temporary-expansion timer',
      );

      semantics.dispose();
    });
  });

  group('expanded (collapsed: false)', () {
    testWidgets('renders the full bar with all named controls', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpBar(tester, collapsed: false);
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
        await pumpBar(tester, collapsed: false);
        final size = tester.getSize(
          find.byType(AnalyticsBarTemporaryExpansion),
        );
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
        collapsed: false,
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
  });
}
