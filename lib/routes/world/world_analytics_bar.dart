import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_client_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/world/level_up_badge_celebration.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/routes/world/xp_border_painter.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The single-column (mobile/narrow) rendering of [WorldUserCluster] — the
/// right column's entry point, pinned to the top of the safe area as a
/// horizontal bar instead of the web cluster's vertical column
/// (routing.instructions.md, "Single-column analytics nav bar"). Same data,
/// same tokens, same tap destinations as the cluster.
///
/// Always the FULL bar: the shell mounts it only on surfaces where it is
/// navigation — the map/cavity ground and the right-column panels it heads.
/// A full-screen chat hosts [AnalyticsHeaderAvatar] in its own app bar
/// instead (no floating chrome stacked over page content), and route-driven
/// detail pages show nothing.
///
/// Content only — the caller (the workspace shell) is responsible for
/// [Positioned] placement, width bounds (the layout is a [Row] with an
/// [Expanded] middle, so it must be given a bounded width), and safe-area
/// padding.
class WorldAnalyticsBar extends StatelessWidget {
  const WorldAnalyticsBar({super.key});

  /// The bar's rendered height: the avatar column governs the Row —
  /// avatar (56) + flag gap (6) + flag (28). The shell's
  /// `analyticsBarAllowance` derives from this so content placed "below the
  /// bar" actually clears it (a widget test pins the rendered height to this
  /// constant).
  static const double expandedHeight = 90.0;

  @override
  Widget build(BuildContext context) => _AnalyticsScope(
    builder: (context, s) => AnalyticsBarView(
      avatarUrl: s.avatarUrl,
      displayName: s.displayName,
      l2: s.l2,
      starsCount: s.starsCount,
      grammarCount: s.grammarCount,
      vocabCount: s.vocabCount,
      level: s.level,
      xpProgress: s.xpProgress,
      isInitializing: s.isInitializing,
      levelUpdates: s.levelUpdates,
      onTrackerTap: (tab) => _openAnalytics(context, tab),
      onAvatarTap: () => _openProfile(context),
      onLevelTap: () => _openLevel(context),
      onFlagTap: () => _openLearningSettings(context),
    ),
  );
}

/// The analytics avatar as a CHAT HEADER action: the circle wearing the XP
/// ring, level badge, and L2 flag, rendered inside the full-screen chat /
/// session app bar (routing.instructions.md, "Single-column analytics nav
/// bar"). A plain button — tapping it opens the analytics summary panel,
/// whose header IS the full bar. This replaced the floating collapsed avatar
/// (and its temporary-expansion timer): chrome stacked over page content was
/// error-prone, and a timed control was a WCAG liability.
class AnalyticsHeaderAvatar extends StatelessWidget {
  const AnalyticsHeaderAvatar({super.key});

  @override
  Widget build(BuildContext context) => _AnalyticsScope(
    builder: (context, s) => Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: CollapsedAvatarView(
        avatarUrl: s.avatarUrl,
        displayName: s.displayName,
        l2: s.l2,
        level: s.level,
        xpProgress: s.xpProgress,
        levelUpdates: s.levelUpdates,
        // App-bar sized: the full-size circle is built for open floating
        // space; at 0.75 the ring + badge + flag fit the toolbar's height.
        scale: 0.75,
        onTap: () => _openAnalyticsSummary(context),
      ),
    ),
  );
}

/// Single-column: a right panel takes the section's slot, so opening one
/// closes an open section sheet (chats list, Courses hub, course card) —
/// otherwise X-ing the panel reveals a stale sheet instead of the map. A live
/// room persists (the header-avatar loop returns to it). The bar renders on
/// narrow only, but gate on the breakpoint so a mid-resize tap stays correct.
bool _closeSections(BuildContext context) =>
    !FluffyThemes.isColumnMode(context);

/// Open the right-docked analytics panel on [tab]'s summary — identical to
/// the web cluster's tracker taps.
void _openAnalytics(BuildContext context, AnalyticsPanelTab tab) => context.go(
  WorkspaceNav.openAnalytics(
    GoRouterState.of(context).uri,
    subpage: tab.indicator,
    closeSections: _closeSections(context),
  ),
);

/// The header avatar opens the analytics summary — the panel whose header is
/// the full bar, so every bar destination is one more tap away.
void _openAnalyticsSummary(BuildContext context) => context.go(
  WorkspaceNav.setRight(GoRouterState.of(context).uri, [
    const PanelToken(PanelTypesEnum.analytics),
  ], closeSections: _closeSections(context)),
);

/// The bar's avatar opens the profile + settings panel, same as the cluster.
void _openProfile(BuildContext context) => context.go(
  WorkspaceNav.openSettings(
    GoRouterState.of(context).uri,
    closeSections: _closeSections(context),
  ),
);

/// The level badge opens the level analytics tab, same as the cluster.
void _openLevel(BuildContext context) => context.go(
  WorkspaceNav.openAnalytics(
    GoRouterState.of(context).uri,
    subpage: ProgressIndicatorEnum.level,
    closeSections: _closeSections(context),
  ),
);

/// The L2 flag opens the learning settings page directly, same as the
/// cluster.
void _openLearningSettings(BuildContext context) => context.go(
  WorkspaceNav.openSettings(
    GoRouterState.of(context).uri,
    page: 'learning',
    closeSections: _closeSections(context),
  ),
);

/// The resolved display values every analytics-nav rendering consumes.
class AnalyticsSnapshot {
  final Uri? avatarUrl;
  final String? displayName;
  final LanguageModel? l2;
  final int starsCount;
  final int grammarCount;
  final int vocabCount;
  final int level;
  final double xpProgress;
  final bool isInitializing;

  /// Level-change signal for the badge's celebration — the same
  /// `levelUpdateStream` the old top-down chat snackbar listened to (#7432),
  /// already subscription-gated. A plain stream value so the renderings below
  /// stay Matrix-free; see [LevelUpBadgeCelebration].
  final Stream<LevelUpdate>? levelUpdates;

  const AnalyticsSnapshot({
    required this.avatarUrl,
    required this.displayName,
    required this.l2,
    required this.starsCount,
    required this.grammarCount,
    required this.vocabCount,
    required this.level,
    required this.xpProgress,
    required this.isInitializing,
    required this.levelUpdates,
  });
}

/// The ONLY Matrix-aware layer of the analytics nav: subscribes to the same
/// streams the cluster does (language, construct updates, awarded-goal room
/// state, derived analytics, own profile) and hands the resolved
/// [AnalyticsSnapshot] to [builder]. Everything below it renders plain values
/// and is testable without a live Client.
class _AnalyticsScope extends StatefulWidget {
  final Widget Function(BuildContext, AnalyticsSnapshot) builder;

  const _AnalyticsScope({required this.builder});

  @override
  State<_AnalyticsScope> createState() => _AnalyticsScopeState();
}

class _AnalyticsScopeState extends State<_AnalyticsScope> {
  bool _profileLoaded = false;

  final ValueNotifier<Uri?> _avatarUrl = ValueNotifier(null);
  final ValueNotifier<String?> _displayName = ValueNotifier(null);

  /// See [AnalyticsSnapshot.levelUpdates]. Created once so consumer rebuilds
  /// don't churn the celebration's subscription; the subscription gate (the
  /// old snackbar's) is applied per event.
  Stream<LevelUpdate>? _levelUpdates;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _levelUpdates ??= Matrix.of(context)
        .analyticsDataService
        .updateDispatcher
        .levelUpdateStream
        .stream
        .where(
          (_) => MatrixState
              .pangeaController
              .subscriptionController
              .showSubscriptionGatedContent,
        );
    if (_profileLoaded) return;
    _profileLoaded = true;
    _loadProfile();
  }

  @override
  void dispose() {
    _avatarUrl.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await Matrix.of(context).client.fetchOwnProfile();
      if (!mounted) return;
      _avatarUrl.value = profile.avatarUrl;
      _displayName.value = profile.displayName;
    } catch (_) {
      // Avatar falls back to the initial; not worth surfacing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final service = matrix.analyticsDataService;

    // The same data wiring as the cluster's pill, nested so every update
    // (language switch, construct counts, awarded stars, level/XP) rebuilds
    // the consumer below with fresh plain values.
    return StreamBuilder(
      stream: MatrixState.pangeaController.userController.languageStream.stream,
      builder: (context, _) {
        final l2 = MatrixState.pangeaController.userController.userL2;
        return StreamBuilder(
          stream: service.updateDispatcher.constructUpdateStream.stream,
          builder: (context, _) {
            final vocab = service.numConstructs(ConstructTypeEnum.vocab);
            final grammar = service.numConstructs(ConstructTypeEnum.morph);
            return StreamBuilder(
              stream: client.onRoomState.stream.where(
                (e) =>
                    e.state.type == PangeaEventTypes.orchestratorAwardedGoals,
              ),
              builder: (context, _) {
                final stars = l2 != null ? client.totalStarsEarned(l2) : 0;
                return FutureBuilder<DerivedAnalyticsDataModel>(
                  future: l2 != null
                      ? service.derivedData(l2.langCodeShort)
                      : Future.value(DerivedAnalyticsDataModel()),
                  builder: (context, snapshot) {
                    final derived = snapshot.data ?? service.cachedDerivedData;
                    return ListenableBuilder(
                      listenable: Listenable.merge([_avatarUrl, _displayName]),
                      builder: (context, _) => widget.builder(
                        context,
                        AnalyticsSnapshot(
                          avatarUrl: _avatarUrl.value,
                          displayName: _displayName.value,
                          l2: l2,
                          starsCount: stars,
                          grammarCount: grammar,
                          vocabCount: vocab,
                          level: derived?.level ?? 1,
                          xpProgress: (derived?.levelProgress ?? 0.0).clamp(
                            0.0,
                            1.0,
                          ),
                          isInitializing: service.isInitializing,
                          levelUpdates: _levelUpdates,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The full bar's plain-values rendering, isolated from the Matrix/analytics
/// data plumbing above so it is unit-testable without a live Client: every
/// value it renders (avatar, name, language, tracker counts, level, XP
/// progress) is a plain field, and every tap is a plain callback. Nothing at
/// or below this widget may call `Matrix.of`, `GoRouterState.of`, or
/// `context.go` — values and callbacks only. (The old temporary-expansion
/// state machine — collapsed rendering, ~3s timer, focus suspension — is
/// gone: full-screen surfaces host [AnalyticsHeaderAvatar] in their own app
/// bar instead of a floating collapsed bar.)
class AnalyticsBarView extends StatelessWidget {
  final Uri? avatarUrl;
  final String? displayName;
  final LanguageModel? l2;
  final int starsCount;
  final int grammarCount;
  final int vocabCount;
  final int level;

  /// 0-1 progress toward the next level, drawn as the avatar's XP ring.
  final double xpProgress;

  /// True while analytics are still loading; the trackers shimmer.
  final bool isInitializing;

  /// Level-change signal for the badge's celebration (a plain stream value;
  /// see [AnalyticsSnapshot.levelUpdates]). Null renders no celebration.
  final Stream<LevelUpdate>? levelUpdates;

  final void Function(AnalyticsPanelTab) onTrackerTap;
  final VoidCallback onAvatarTap;
  final VoidCallback onLevelTap;
  final VoidCallback onFlagTap;

  /// Builds the L2 flag chip at the requested size. Null uses the real
  /// [ClusterLanguageFlag]; tests inject a plain stand-in because the real
  /// chip loads a network SVG whose async parse throws into the test zone.
  final Widget Function(
    LanguageModel language,
    VoidCallback onTap,
    double width,
    double height,
    double fontSize,
  )?
  flagBuilder;

  const AnalyticsBarView({
    required this.avatarUrl,
    required this.displayName,
    required this.l2,
    required this.starsCount,
    required this.grammarCount,
    required this.vocabCount,
    required this.level,
    required this.xpProgress,
    required this.isInitializing,
    required this.onTrackerTap,
    required this.onAvatarTap,
    required this.onLevelTap,
    required this.onFlagTap,
    this.levelUpdates,
    this.flagBuilder,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _ExpandedAnalyticsBar(
    avatarUrl: avatarUrl,
    displayName: displayName,
    l2: l2,
    starsCount: starsCount,
    grammarCount: grammarCount,
    vocabCount: vocabCount,
    level: level,
    xpProgress: xpProgress,
    isInitializing: isInitializing,
    levelUpdates: levelUpdates,
    onTrackerTap: onTrackerTap,
    onAvatarTap: onAvatarTap,
    onLevelTap: onLevelTap,
    onFlagTap: onFlagTap,
    flagBuilder: flagBuilder,
  );
}

/// The full horizontal bar: level badge at the left end, the gold powerups
/// pill (Stars / Grammar / Vocabulary) in the middle, the avatar with its XP
/// ring at the right, and the L2 flag below the avatar
/// (routing.instructions.md, "Single-column analytics nav bar"). Reuses the
/// cluster's visual atoms ([ClusterAvatar], [ClusterTrackerButton],
/// [ClusterLevelMedal], [ClusterLanguageFlag]) so the look and the
/// tooltip/semantics labels stay identical to web. Plain values only — no
/// Matrix or router reads (see [AnalyticsBarView]).
class _ExpandedAnalyticsBar extends StatelessWidget {
  final Uri? avatarUrl;
  final String? displayName;
  final LanguageModel? l2;
  final int starsCount;
  final int grammarCount;
  final int vocabCount;
  final int level;
  final double xpProgress;
  final bool isInitializing;
  final Stream<LevelUpdate>? levelUpdates;
  final void Function(AnalyticsPanelTab) onTrackerTap;
  final VoidCallback onAvatarTap;
  final VoidCallback onLevelTap;
  final VoidCallback onFlagTap;
  final Widget Function(
    LanguageModel language,
    VoidCallback onTap,
    double width,
    double height,
    double fontSize,
  )?
  flagBuilder;

  const _ExpandedAnalyticsBar({
    required this.avatarUrl,
    required this.displayName,
    required this.l2,
    required this.starsCount,
    required this.grammarCount,
    required this.vocabCount,
    required this.level,
    required this.xpProgress,
    required this.isInitializing,
    required this.levelUpdates,
    required this.onTrackerTap,
    required this.onAvatarTap,
    required this.onLevelTap,
    required this.onFlagTap,
    required this.flagBuilder,
  });

  static const double _avatarSize = 56.0;
  static const double _xpStroke = 4.0;
  static const double _pillInnerRadius = 20.0;

  /// Half the hex badge's width — how far it sticks out past the pill's
  /// left edge (the Figma overhang).
  static const double _hexBadgeOverhang = 21.0;

  // Pill interior: extra left inset so the trackers clear the hex badge's
  // inner half, tight vertical padding for the compact bar-height pill.
  static const double _pillTrackerClearance = 10.0;
  static const double _pillVerticalPadding = 2.0;
  static const double _pillRightPadding = 14.0;

  /// Gap between the pill+badge unit and the avatar column.
  static const double _pillAvatarGap = 12.0;

  // The bar's hex badge is smaller than [_HexLevelBadge]'s web-facing
  // defaults, per the Figma bar frame.
  static const double _badgeWidth = 42.0;
  static const double _badgeHeight = 36.0;
  static const double _badgeFontSize = 16.0;

  // The mobile flag is smaller than web's 52x36, per the Figma bar frame.
  static const double _flagWidth = 40.0;
  static const double _flagHeight = 28.0;
  static const double _flagFontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final l2 = this.l2;
    return Semantics(
      label: L10n.of(context).analyticsAndSettingsLabel,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            // Right-justified, up against the avatar — the pill and avatar
            // read as one cluster at the bar's right end, like the web
            // cluster's tight column.
            child: Align(
              alignment: Alignment.centerRight,
              // The medal + XP-bordered pill are ONE unit, exactly like the web
              // cluster rotated horizontal: the pill's frame IS the XP ring
              // (gold growing from the badge's top, clockwise, meeting at its
              // bottom) and the level medal overhangs the pill's LEFT end —
              // the mirror of web's bottom-center overhang.
              child: Stack(
                alignment: Alignment.centerLeft,
                // The badge's level-up celebration paints just outside the
                // pill unit's bounds (pulse + chip); don't clip it. The
                // celebration is decoration-only (IgnorePointer), so the
                // hit-test caveat below still only concerns the badge itself.
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: _hexBadgeOverhang),
                    child: CustomPaint(
                      painter: XpBorderPainter(
                        progress: xpProgress,
                        trackColor: const Color.fromARGB(130, 135, 135, 135),
                        progressColor: AppConfig.goldByTheme(context),
                        stroke: _xpStroke,
                        radius: _pillInnerRadius + _xpStroke / 2,
                        anchor: XpBorderAnchor.leftCenter,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(_xpStroke),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(
                              _pillInnerRadius,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          padding: const EdgeInsets.fromLTRB(
                            _hexBadgeOverhang + _pillTrackerClearance,
                            _pillVerticalPadding,
                            _pillRightPadding,
                            _pillVerticalPadding,
                          ),
                          child: _PowerupsRow(
                            starsCount: starsCount,
                            grammarCount: grammarCount,
                            vocabCount: vocabCount,
                            isInitializing: isInitializing,
                            onTap: onTrackerTap,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Half-overlapping the pill's left end, vertically centered
                  // (the Figma hexagon). Kept INSIDE the Stack's bounds — a
                  // negative Positioned paints but does not hit-test, which
                  // silently killed the badge's tap (test-caught).
                  Positioned(
                    left: 0,
                    child: Material(
                      type: MaterialType.transparency,
                      child: LevelUpBadgeCelebration(
                        levelUpdates: levelUpdates,
                        child: _HexLevelBadge(
                          level: level,
                          onTap: onLevelTap,
                          width: _badgeWidth,
                          height: _badgeHeight,
                          fontSize: _badgeFontSize,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: _pillAvatarGap),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClusterAvatar(
                avatarUrl: avatarUrl,
                name: displayName,
                onTap: onAvatarTap,
                size: _avatarSize,
              ),
              if (l2 != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child:
                      flagBuilder?.call(
                        l2,
                        onFlagTap,
                        _flagWidth,
                        _flagHeight,
                        _flagFontSize,
                      ) ??
                      ClusterLanguageFlag(
                        language: l2,
                        onTap: onFlagTap,
                        width: _flagWidth,
                        height: _flagHeight,
                        fontSize: _flagFontSize,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The gold powerups pill's three trackers, laid out horizontally instead of
/// the web cluster's vertical stack. Same counts, same tooltip/semantics
/// labels, same shimmer-while-initializing as the cluster's pill, so the two
/// surfaces never disagree — but all values arrive as plain fields.
class _PowerupsRow extends StatelessWidget {
  final int starsCount;
  final int grammarCount;
  final int vocabCount;
  final bool isInitializing;
  final void Function(AnalyticsPanelTab) onTap;

  const _PowerupsRow({
    required this.starsCount,
    required this.grammarCount,
    required this.vocabCount,
    required this.isInitializing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // No decoration of its own: the XP-bordered pill Container in
    // [_ExpandedAnalyticsBar] is the field these trackers sit on (mirroring
    // the web pill's structure).
    final content = Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClusterTrackerButton(
            indicator: ProgressIndicatorEnum.stars,
            count: starsCount,
            onTap: () => onTap(AnalyticsPanelTab.sessions),
          ),
          ClusterTrackerButton(
            indicator: ProgressIndicatorEnum.morphsUsed,
            count: grammarCount,
            onTap: () => onTap(AnalyticsPanelTab.grammar),
          ),
          ClusterTrackerButton(
            indicator: ProgressIndicatorEnum.wordsUsed,
            count: vocabCount,
            onTap: () => onTap(AnalyticsPanelTab.vocab),
          ),
        ],
      ),
    );

    return isInitializing
        ? Shimmer.fromColors(
            baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            highlightColor: Theme.of(context).colorScheme.surface,
            child: content,
          )
        : content;
  }
}

/// The narrow bar's level badge: the Figma hexagon (pointy left/right, flat
/// top/bottom) with a darker gold border and the level number centered —
/// unlike the web cluster's tailed shield medal, which hangs its number low
/// and carries the notched ribbon bottom the mobile design drops. Same
/// semantics contract as [ClusterLevelMedal] (named button, tap opens Level).
class _HexLevelBadge extends StatelessWidget {
  final int level;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double fontSize;

  const _HexLevelBadge({
    required this.level,
    required this.onTap,
    this.width = 48.0,
    this.height = 42.0,
    this.fontSize = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    final label = '${L10n.of(context).level} $level';
    final fill = AppConfig.goldByTheme(context);
    final hsl = HSLColor.fromColor(fill);
    final border = hsl
        .withLightness((hsl.lightness * 0.72).clamp(0.0, 1.0))
        .toColor();
    return Tooltip(
      message: label,
      // Semantics below names this; exclude the Tooltip so the label isn't
      // announced twice.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        container: true,
        excludeSemantics: true,
        // Expose the tap on the announced node for assistive tech (#7185).
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CustomPaint(
            size: Size(width, height),
            painter: _HexBadgePainter(fill: fill, border: border),
            child: SizedBox(
              width: width,
              height: height,
              child: Center(
                child: Text(
                  '$level',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the badge hexagon: vertices at the horizontal extremes, flat top and
/// bottom edges, gold fill with a darker gold outline (the Figma component).
class _HexBadgePainter extends CustomPainter {
  final Color fill;
  final Color border;

  const _HexBadgePainter({required this.fill, required this.border});

  Path _hex(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, h / 2)
      ..lineTo(w * 0.25, 0)
      ..lineTo(w * 0.75, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w * 0.75, h)
      ..lineTo(w * 0.25, h)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _hex(size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_HexBadgePainter old) =>
      old.fill != fill || old.border != border;
}

/// The avatar circle wearing the XP ring, the level badge, and the small
/// flag (Figma collapsed component) — one tap target, announced as a single
/// button. Plain values only; [AnalyticsHeaderAvatar] is its Matrix-aware
/// host, mounting it in a full-screen chat's app bar (routing.instructions.md
/// → "Single-column analytics nav bar"). [scale] shrinks the whole cluster
/// proportionally so it fits a toolbar.
class CollapsedAvatarView extends StatelessWidget {
  final Uri? avatarUrl;
  final String? displayName;
  final LanguageModel? l2;
  final int level;
  final double xpProgress;
  final VoidCallback onTap;
  final double scale;

  /// Level-change signal for the mini badge's celebration (a plain stream
  /// value; see [AnalyticsSnapshot.levelUpdates]). Null renders no
  /// celebration.
  final Stream<LevelUpdate>? levelUpdates;

  const CollapsedAvatarView({
    required this.avatarUrl,
    required this.displayName,
    required this.l2,
    required this.level,
    required this.xpProgress,
    required this.onTap,
    this.scale = 1.0,
    this.levelUpdates,
    this.flagBuilder,
    super.key,
  });

  final Widget Function(
    LanguageModel language,
    VoidCallback onTap,
    double width,
    double height,
    double fontSize,
  )?
  flagBuilder;

  // Base (scale 1.0) geometry — the floating-space size the cluster was
  // designed at; every dimension multiplies by [scale] so the proportions
  // hold at toolbar sizes.
  static const double _xpStrokeBase = 4.0;
  static const double _avatarSizeBase = 44.0;
  static const double _flagWidthBase = 28.0;
  static const double _flagHeightBase = 20.0;
  static const double _flagFontSizeBase = 11.0;

  // Miniature hex badge pinned over the avatar's top-left, and the flag
  // hanging under its bottom edge — the collapsed echo of the bar cluster.
  static const double _badgeTopOffsetBase = -6.0;
  static const double _badgeLeftOffsetBase = -10.0;
  static const double _badgeWidthBase = 30.0;
  static const double _badgeHeightBase = 26.0;
  static const double _badgeFontSizeBase = 13.0;
  static const double _flagBottomOffsetBase = -10.0;

  double get _xpStroke => _xpStrokeBase * scale;
  double get _avatarSize => _avatarSizeBase * scale;
  double get _flagWidth => _flagWidthBase * scale;
  double get _flagHeight => _flagHeightBase * scale;
  double get _flagFontSize => _flagFontSizeBase * scale;
  double get _badgeTopOffset => _badgeTopOffsetBase * scale;
  double get _badgeLeftOffset => _badgeLeftOffsetBase * scale;
  double get _badgeWidth => _badgeWidthBase * scale;
  double get _badgeHeight => _badgeHeightBase * scale;
  double get _badgeFontSize => _badgeFontSizeBase * scale;
  double get _flagBottomOffset => _flagBottomOffsetBase * scale;

  @override
  Widget build(BuildContext context) {
    final l2 = this.l2;
    final label = L10n.of(context).analyticsAndSettingsLabel;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: label,
        // The Semantics below already names this control; exclude the Tooltip
        // so its message isn't announced twice.
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: label,
          // A bounded node of its own: without `container` the annotation
          // merges into the stretched ancestor, so assistive tech (and the
          // widget tests' semantics taps) target the full-width bar area
          // instead of the circle.
          container: true,
          excludeSemantics: true,
          // Expose the tap on the announced node for assistive tech (#7185).
          onTap: onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(_avatarSize + 2 * _xpStroke),
                  painter: CircularXpRingPainter(
                    progress: xpProgress,
                    trackColor: const Color.fromARGB(130, 135, 135, 135),
                    progressColor: AppConfig.goldByTheme(context),
                    stroke: _xpStroke,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(_xpStroke),
                    child: ClusterAvatar(
                      avatarUrl: avatarUrl,
                      name: displayName,
                      onTap: onTap,
                      size: _avatarSize,
                    ),
                  ),
                ),
                Positioned(
                  top: _badgeTopOffset,
                  left: _badgeLeftOffset,
                  child: IgnorePointer(
                    child: Material(
                      type: MaterialType.transparency,
                      child: LevelUpBadgeCelebration(
                        levelUpdates: levelUpdates,
                        child: _HexLevelBadge(
                          level: level,
                          onTap: onTap,
                          width: _badgeWidth,
                          height: _badgeHeight,
                          fontSize: _badgeFontSize,
                        ),
                      ),
                    ),
                  ),
                ),
                if (l2 != null)
                  Positioned(
                    bottom: _flagBottomOffset,
                    child: IgnorePointer(
                      child:
                          flagBuilder?.call(
                            l2,
                            onTap,
                            _flagWidth,
                            _flagHeight,
                            _flagFontSize,
                          ) ??
                          ClusterLanguageFlag(
                            language: l2,
                            onTap: onTap,
                            width: _flagWidth,
                            height: _flagHeight,
                            fontSize: _flagFontSize,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the collapsed avatar's XP ring: a full gray circular track with a
/// gold arc filling clockwise from the top for [progress] (0-1) of the way to
/// the next level. The cluster's `XpBorderPainter` traces the powerups pill's
/// rounded-rect outline instead, so the circular avatar needs this simpler
/// circular counterpart rather than reusing it as-is.
class CircularXpRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double stroke;

  const CircularXpRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = progressColor,
    );
  }

  @override
  bool shouldRepaint(CircularXpRingPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.stroke != stroke;
}
