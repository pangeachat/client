import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_client_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The single-column (mobile/narrow) rendering of [WorldUserCluster] — the
/// right column's entry point, pinned to the top of the safe area as a
/// horizontal bar instead of the web cluster's vertical column
/// (routing.instructions.md, "Single-column analytics bar"). Same data, same
/// tokens, same tap destinations as the cluster; only the layout and the
/// collapsed-on-full-screen behavior are mobile-specific.
///
/// This widget is the bar's ONLY Matrix-aware layer: it subscribes to the
/// same streams the cluster does (language, construct updates, awarded-goal
/// room state, derived analytics) and hands the resolved display values to
/// [AnalyticsBarTemporaryExpansion] as plain fields, so everything below it
/// is testable without a live Client.
///
/// Content only — the caller (the workspace shell) is responsible for
/// [Positioned] placement, width bounds (the expanded layout is a [Row] with
/// an [Expanded] middle, so it must be given a bounded width), and safe-area
/// padding.
class WorldAnalyticsBar extends StatefulWidget {
  /// True on full-screen surfaces (a live chat, an activity start/join): the
  /// bar renders as the single avatar circle until tapped, per the Figma
  /// collapsed component.
  final bool collapsed;

  const WorldAnalyticsBar({required this.collapsed, super.key});

  /// How long a tap on the collapsed avatar keeps the bar temporarily
  /// expanded before it auto-collapses, absent further interaction or focus
  /// (routing.instructions.md, "Single-column analytics bar"). Overridable
  /// only for tests, so they don't have to wait out the real duration.
  @visibleForTesting
  static Duration temporaryExpansionDuration = const Duration(seconds: 3);

  @override
  State<WorldAnalyticsBar> createState() => _WorldAnalyticsBarState();
}

class _WorldAnalyticsBarState extends State<WorldAnalyticsBar> {
  bool _profileLoaded = false;

  final ValueNotifier<Uri?> _avatarUrl = ValueNotifier(null);
  final ValueNotifier<String?> _displayName = ValueNotifier(null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  /// Open the right-docked analytics panel on [tab]'s summary — identical to
  /// the web cluster's tracker taps.
  void _openAnalytics(AnalyticsPanelTab tab) => context.go(
    WorkspaceNav.setRight(GoRouterState.of(context).uri, [
      PanelToken('analytics', tab.name),
    ]),
  );

  /// The avatar opens the profile + settings panel, same as the cluster.
  void _openProfile() =>
      context.go(WorkspaceNav.openSettings(GoRouterState.of(context).uri));

  /// The level badge opens the level analytics tab, same as the cluster.
  void _openLevel() => context.go(
    WorkspaceNav.setRight(GoRouterState.of(context).uri, [
      const PanelToken('analytics', 'level'),
    ]),
  );

  /// The L2 flag opens the learning settings page directly, same as the
  /// cluster.
  void _openLearningSettings() => context.go(
    WorkspaceNav.openSettings(GoRouterState.of(context).uri, page: 'learning'),
  );

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final service = matrix.analyticsDataService;

    // The same data wiring as the cluster's pill, nested so every update
    // (language switch, construct counts, awarded stars, level/XP) rebuilds
    // the expansion below with fresh plain values.
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
                      builder: (context, _) => AnalyticsBarTemporaryExpansion(
                        collapsed: widget.collapsed,
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
                        onTrackerTap: _openAnalytics,
                        onAvatarTap: _openProfile,
                        onLevelTap: _openLevel,
                        onFlagTap: _openLearningSettings,
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

/// The collapse/expand/timer state machine, isolated from the Matrix/analytics
/// data plumbing above so it is unit-testable without a live Client: every
/// value it renders (avatar, name, language, tracker counts, level, XP
/// progress) is a plain field, and every tap is a plain callback. Nothing at
/// or below this widget may call `Matrix.of`, `GoRouterState.of`, or
/// `context.go` — values and callbacks only. Owns:
///  - resetting to the base [collapsed] state whenever that flips (the
///    surface went full-screen or stopped being full-screen);
///  - the ~3s temporary-expansion timer a tap on the collapsed avatar starts;
///  - suspending/restarting that timer while a descendant holds focus, so
///    keyboard/switch/screen-reader users are never raced by a timeout
///    (WCAG 2.2.1 — routing.instructions.md, "Single-column analytics bar");
///  - restarting the timer on any tap inside the bar.
@visibleForTesting
class AnalyticsBarTemporaryExpansion extends StatefulWidget {
  final bool collapsed;
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

  const AnalyticsBarTemporaryExpansion({
    required this.collapsed,
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
    this.flagBuilder,
    super.key,
  });

  @override
  State<AnalyticsBarTemporaryExpansion> createState() =>
      _AnalyticsBarTemporaryExpansionState();
}

class _AnalyticsBarTemporaryExpansionState
    extends State<AnalyticsBarTemporaryExpansion> {
  final FocusNode _focusScopeNode = FocusNode(
    debugLabel: 'WorldAnalyticsBar temporary expansion',
  );

  bool _temporarilyExpanded = false;
  Timer? _collapseTimer;
  bool _focusWithin = false;

  bool get _expanded => !widget.collapsed || _temporarilyExpanded;

  @override
  void didUpdateWidget(covariant AnalyticsBarTemporaryExpansion oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Base state changed from full-screen to non-full-screen (or vice versa):
    // the temporary expansion no longer means anything, so reset it and drop
    // any pending auto-collapse.
    if (oldWidget.collapsed != widget.collapsed) {
      _temporarilyExpanded = false;
      _cancelTimer();
    }
  }

  @override
  void dispose() {
    _cancelTimer();
    _focusScopeNode.dispose();
    super.dispose();
  }

  void _cancelTimer() {
    _collapseTimer?.cancel();
    _collapseTimer = null;
  }

  /// (Re)starts the auto-collapse countdown, unless a descendant currently
  /// holds focus — in which case the timer stays suspended until focus
  /// leaves (see [_onFocusChange]).
  void _restartTimer() {
    _cancelTimer();
    if (_focusWithin) return;
    _collapseTimer = Timer(
      WorldAnalyticsBar.temporaryExpansionDuration,
      _autoCollapse,
    );
  }

  void _autoCollapse() {
    if (!mounted) return;
    setState(() => _temporarilyExpanded = false);
  }

  void _onFocusChange(bool hasFocus) {
    _focusWithin = hasFocus;
    if (hasFocus) {
      // A focused descendant must never be raced by the timeout (WCAG 2.2.1).
      _cancelTimer();
    } else if (_temporarilyExpanded) {
      // Focus left the bar while it was only temporarily expanded: resume the
      // countdown from a fresh window rather than collapsing immediately.
      _restartTimer();
    }
  }

  void _expandTemporarily() {
    setState(() => _temporarilyExpanded = true);
    _restartTimer();
  }

  /// Any tap inside an already-expanded bar restarts the countdown so an
  /// active user (tapping a tracker, opening settings) is never collapsed out
  /// from under them mid-interaction.
  void _onInteraction() {
    if (widget.collapsed && _temporarilyExpanded) _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    final content = _expanded
        ? _ExpandedAnalyticsBar(
            avatarUrl: widget.avatarUrl,
            displayName: widget.displayName,
            l2: widget.l2,
            starsCount: widget.starsCount,
            grammarCount: widget.grammarCount,
            vocabCount: widget.vocabCount,
            level: widget.level,
            xpProgress: widget.xpProgress,
            isInitializing: widget.isInitializing,
            onTrackerTap: (tab) {
              _onInteraction();
              widget.onTrackerTap(tab);
            },
            onAvatarTap: () {
              _onInteraction();
              widget.onAvatarTap();
            },
            onLevelTap: () {
              _onInteraction();
              widget.onLevelTap();
            },
            onFlagTap: () {
              _onInteraction();
              widget.onFlagTap();
            },
            flagBuilder: widget.flagBuilder,
          )
        : _CollapsedAnalyticsAvatar(
            avatarUrl: widget.avatarUrl,
            displayName: widget.displayName,
            l2: widget.l2,
            level: widget.level,
            xpProgress: widget.xpProgress,
            onTap: _expandTemporarily,
            flagBuilder: widget.flagBuilder,
          );

    return Focus(
      focusNode: _focusScopeNode,
      onFocusChange: _onFocusChange,
      // A parent Focus that only tracks descendant focus, not a stop of its
      // own — descendants (trackers, avatar, flag) keep their own
      // focusability; this just observes whether any of them is focused.
      skipTraversal: true,
      canRequestFocus: false,
      child: content,
    );
  }
}

/// The full horizontal bar: level badge at the left end, the gold powerups
/// pill (Stars / Grammar / Vocabulary) in the middle, the avatar with its XP
/// ring at the right, and the L2 flag below the avatar
/// (routing.instructions.md, "Single-column analytics bar"). Reuses the
/// cluster's visual atoms ([ClusterAvatar], [ClusterTrackerButton],
/// [ClusterLevelMedal], [ClusterLanguageFlag]) so the look and the
/// tooltip/semantics labels stay identical to web. Plain values only — no
/// Matrix or router reads (see [AnalyticsBarTemporaryExpansion]).
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
    required this.onTrackerTap,
    required this.onAvatarTap,
    required this.onLevelTap,
    required this.onFlagTap,
    required this.flagBuilder,
  });

  static const double _avatarSize = 56.0;
  static const double _xpStroke = 4.0;

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
          Material(
            type: MaterialType.transparency,
            child: ClusterLevelMedal(level: level, onTap: onLevelTap),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: _PowerupsRow(
                starsCount: starsCount,
                grammarCount: grammarCount,
                vocabCount: vocabCount,
                isInitializing: isInitializing,
                onTap: onTrackerTap,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                painter: CircularXpRingPainter(
                  progress: xpProgress,
                  trackColor: const Color.fromARGB(130, 135, 135, 135),
                  progressColor: AppConfig.goldByTheme(context),
                  stroke: _xpStroke,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(_xpStroke),
                  child: ClusterAvatar(
                    avatarUrl: avatarUrl,
                    name: displayName,
                    onTap: onAvatarTap,
                    size: _avatarSize,
                  ),
                ),
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
    final content = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(100),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
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

/// The collapsed state: a single avatar circle wearing the XP ring, the level
/// badge, and the small flag (Figma collapsed component). Tapping it is the
/// only affordance; it temporarily expands the full bar. Plain values only.
class _CollapsedAnalyticsAvatar extends StatelessWidget {
  final Uri? avatarUrl;
  final String? displayName;
  final LanguageModel? l2;
  final int level;
  final double xpProgress;
  final VoidCallback onTap;

  const _CollapsedAnalyticsAvatar({
    required this.avatarUrl,
    required this.displayName,
    required this.l2,
    required this.level,
    required this.xpProgress,
    required this.onTap,
    required this.flagBuilder,
  });

  final Widget Function(
    LanguageModel language,
    VoidCallback onTap,
    double width,
    double height,
    double fontSize,
  )?
  flagBuilder;

  static const double _xpStroke = 4.0;
  static const double _avatarSize = 44.0;
  static const double _flagWidth = 28.0;
  static const double _flagHeight = 20.0;
  static const double _flagFontSize = 11.0;

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
                  size: const Size.square(_avatarSize + 2 * _xpStroke),
                  painter: CircularXpRingPainter(
                    progress: xpProgress,
                    trackColor: const Color.fromARGB(130, 135, 135, 135),
                    progressColor: AppConfig.goldByTheme(context),
                    stroke: _xpStroke,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(_xpStroke),
                    child: ClusterAvatar(
                      avatarUrl: avatarUrl,
                      name: displayName,
                      onTap: onTap,
                      size: _avatarSize,
                    ),
                  ),
                ),
                Positioned(
                  top: -6,
                  left: -6,
                  child: IgnorePointer(
                    child: Material(
                      type: MaterialType.transparency,
                      child: ClusterLevelMedal(level: level, onTap: onTap),
                    ),
                  ),
                ),
                if (l2 != null)
                  Positioned(
                    bottom: -10,
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
