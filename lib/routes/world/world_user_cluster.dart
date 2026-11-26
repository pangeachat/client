import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_flag_chip.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/features/tutorials/tutorial_target_ids.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_badge.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/routes/world/compact_count.dart';
import 'package:fluffychat/routes/world/level_up_badge_celebration.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model_builder.dart';
import 'package:fluffychat/routes/world/xp_border_painter.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/workspace_shell.dart';
import 'package:fluffychat/widgets/users/level_ribbon.dart';

/// The persistent top-right cluster over the world map (world_v2): the user's
/// avatar wrapped in a clockwise XP ring (gray track that fills gold toward the
/// next level), a gold "powerups" pill of three tappable trackers (Sessions /
/// Grammar / Vocabulary) with the level medal overhanging its base, and the
/// active L2 flag below. Tapping a tracker opens that metric's analytics docked
/// on the right; the avatar opens profile/settings; the level medal opens the
/// level tab; the flag opens learning settings. All data is client-side (see
/// analytics-system.instructions.md); the cluster listens to the analytics
/// update streams so counts/level/XP stay live. Look follows Figma
/// `AvatarLangFlags` (12935:46894). See routing.instructions.md.
class WorldUserCluster extends StatelessWidget {
  const WorldUserCluster({super.key});

  @override
  Widget build(BuildContext context) {
    // Which analytics panel is open — chrome-level derivation from the URL, so
    // the tracker whose panel is showing stays highlighted (#7977). Read here
    // (not below) so the plain-values internals stay route-free and testable.
    final selectedTab = activeAnalyticsTabFor(GoRouterState.of(context).uri);
    return UserClusterViewModelBuilder(
      builder: (context, viewModel) => WorldUserClusterInternal(
        viewModel: viewModel,
        selectedTab: selectedTab,
      ),
    );
  }
}

class WorldUserClusterInternal extends StatelessWidget {
  final UserClusterViewModel viewModel;

  /// The analytics metric whose panel is open, highlighted in the pill; null
  /// when none is open ([activeAnalyticsTabFor]).
  final ProgressIndicatorEnum? selectedTab;

  const WorldUserClusterInternal({
    super.key,
    required this.viewModel,
    this.selectedTab,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: viewModel.languageStream,
      builder: (context, _) {
        final l2 = viewModel.userL2;
        return Semantics(
          label: L10n.of(context).analyticsAndSettingsLabel,
          sortKey: WorkspaceOrder.cluster.sortKey,
          container: true,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ListenableBuilder(
                  listenable: Listenable.merge([
                    viewModel.avatarUrl,
                    viewModel.displayName,
                  ]),
                  builder: (context, _) => ClusterAvatar(
                    avatarUrl: viewModel.avatarUrl.value,
                    name: viewModel.displayName.value,
                    onTap: () => viewModel.openProfile(context),
                  ),
                ),
                const SizedBox(height: 8),
                _PowerupsPill(viewModel: viewModel, selectedTab: selectedTab),
                if (l2 != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: ClusterLanguageFlag(
                      language: l2,
                      onTap: () => viewModel.openLearningSettings(context),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The circular user avatar at the top of the cluster. Opens profile/settings.
/// Public (not `_`-prefixed) and its size overridable so [WorldAnalyticsBar] —
/// the mobile single-column rendering of this same cluster
/// (routing.instructions.md, "Single-column analytics nav bar") — can reuse it
/// verbatim (including at the collapsed bar's smaller size) rather than
/// duplicating the avatar + tooltip + semantics wiring. This is the one
/// mechanical visibility change made to this file for that reuse; no behavior
/// changed for the cluster's own usage (the default matches the old fixed
/// `_size`).
class ClusterAvatar extends StatelessWidget {
  final Uri? avatarUrl;
  final String? name;
  final VoidCallback onTap;
  final double size;

  const ClusterAvatar({
    required this.avatarUrl,
    required this.name,
    required this.onTap,
    this.size = _defaultSize,
    super.key,
  });

  static const double _defaultSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final label = L10n.of(context).settings;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: label,
        // The target below already names this control; without this the
        // Tooltip's own message is announced too, doubling the accessible name
        // ("Account Account"). See accessibility.instructions.md.
        excludeFromSemantics: true,
        child: FocusRingTapTarget(
          onTap: onTap,
          shape: const CircleBorder(),
          label: label,
          child: Avatar(
            mxContent: avatarUrl,
            name: name,
            size: size,
            showPresence: false,
          ),
        ),
      ),
    );
  }
}

/// The gold "powerups" pill: a white inner stack of the three trackers with the
/// level medal overhanging its base. Follows Figma `AvatarLangFlags`.
class _PowerupsPill extends StatelessWidget {
  final UserClusterViewModel viewModel;
  final ProgressIndicatorEnum? selectedTab;
  const _PowerupsPill({required this.viewModel, this.selectedTab});

  static const double _xpStroke = 5.0;
  static const double _innerRadius = 20.0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: viewModel.constructUpdateStream,
      builder: (context, _) {
        final vocab = viewModel.numVocabConstructs;
        final grammar = viewModel.numGrammarConstruct;

        final content = FutureBuilder<DerivedAnalyticsDataModel>(
          future: viewModel.derivedAnalyticsData,
          builder: (context, snapshot) {
            final derived =
                snapshot.data ?? viewModel.cachedDerivedAnalyticsData;
            final level = derived?.level ?? 1;
            final progress = (derived?.levelProgress ?? 0.0).clamp(0.0, 1.0);

            return Stack(
              alignment: Alignment.bottomCenter,
              // The medal's level-up celebration paints just outside the
              // pill's bounds (badge pulse + chip); don't clip it.
              clipBehavior: Clip.none,
              children: [
                // The pill's frame IS the XP ring: an opaque track that fills gold
                // clockwise from the bottom-center (where the level medal sits) toward
                // the next level. The trackers sit on a white field inside it; there is
                // no solid gold fill — the only gold is the XP progress.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      painter: XpBorderPainter(
                        progress: progress,
                        trackColor: XpBorderPainter.trackColorFor(
                          Theme.of(context),
                        ),
                        progressColor: XpBorderPainter.arcColorFor(
                          Theme.of(context),
                        ),
                        stroke: _xpStroke,
                        innerRadius: _innerRadius,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(
                          _xpStroke + XpBorderPainter.trackExtra,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(_innerRadius),
                          ),
                          clipBehavior: Clip.antiAlias,
                          padding: EdgeInsets.all(0),
                          child: Material(
                            type: MaterialType.transparency,
                            // One width for all three keys, so the column reads
                            // as one segmented strip rather than three
                            // count-sized lozenges.
                            child: IntrinsicWidth(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  StreamBuilder(
                                    stream: viewModel.starsUpdateStream,
                                    builder: (context, _) {
                                      final stars = viewModel.starsEarned;
                                      return ClusterTrackerButton(
                                        indicator: ProgressIndicatorEnum.stars,
                                        segment: TrackerSegment.first,
                                        axis: Axis.vertical,
                                        count: stars,
                                        selected:
                                            selectedTab ==
                                            ProgressIndicatorEnum.stars,
                                        onTap: () => viewModel.openAnalytics(
                                          context,
                                          AnalyticsPanelTab.sessions,
                                        ),
                                      );
                                    },
                                  ),
                                  ClusterTrackerButton(
                                    indicator: ProgressIndicatorEnum.morphsUsed,
                                    segment: TrackerSegment.middle,
                                    axis: Axis.vertical,
                                    count: grammar,
                                    selected:
                                        selectedTab ==
                                        ProgressIndicatorEnum.morphsUsed,
                                    onTap: () => viewModel.openAnalytics(
                                      context,
                                      AnalyticsPanelTab.grammar,
                                    ),
                                  ),
                                  ClusterTrackerButton(
                                    indicator: ProgressIndicatorEnum.wordsUsed,
                                    segment: TrackerSegment.last,
                                    axis: Axis.vertical,
                                    tutorialTargetId:
                                        TutorialTargetIds.analyticsVocabTracker,
                                    count: vocab,
                                    selected:
                                        selectedTab ==
                                        ProgressIndicatorEnum.wordsUsed,
                                    onTap: () => viewModel.openAnalytics(
                                      context,
                                      AnalyticsPanelTab.vocab,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 30),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  child: Material(
                    type: MaterialType.transparency,
                    child: LevelUpBadgeCelebration(
                      levelUpdates: viewModel.levelUpdates,
                      child: ClusterLevelMedal(
                        level: level,
                        selected: selectedTab == ProgressIndicatorEnum.level,
                        onTap: () => viewModel.openLevel(context),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );

        return viewModel.isAnalyticsInitializing
            ? Shimmer.fromColors(
                baseColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                highlightColor: Theme.of(context).colorScheme.surface,
                child: content,
              )
            : content;
      },
    );
  }
}

/// Where a tracker sits in its pill's segmented strip: the outer corners
/// follow the pill's rounding, the corners it shares with a neighbour stay
/// tight, so the three keys read as one segmented control.
enum TrackerSegment { first, middle, last }

/// One tracker in the powerups pill: a physical key, flush with the XP ring
/// at rest (a raised lip would read as standing above it), icon over count.
/// Tapping opens that metric's analytics tab. The key sinks below the ring
/// while held down and STAYS sunk while its panel is open,
/// so the open panel reads as a pressed-in key (#7977). Public so
/// [WorldAnalyticsBar] can lay the same three trackers out horizontally.
/// The displayed count abbreviates above 999 ([compactCount]) so the pill
/// never outgrows the allocator's fixed cluster gutter; the semantics label
/// carries the exact count.
class ClusterTrackerButton extends StatefulWidget {
  /// How far a key sinks below the pill's ring when pressed — the same depth
  /// as the toolbar's [PressableButton]s.
  static const double keyDepth = 4.0;

  final ProgressIndicatorEnum indicator;
  final int count;
  final VoidCallback onTap;

  /// Whether this tracker's analytics panel is the one currently open — then
  /// the key stays pressed in, so the pill shows what is on screen (#7977).
  /// Ignored while a live practice badge occupies the tracker.
  final bool selected;

  /// Position in the strip and the strip's direction, which together pick the
  /// key's corner rounding.
  final TrackerSegment segment;
  final Axis axis;

  /// Sizing knobs so the narrow analytics bar can render the compact variant
  /// (the Figma mobile pill); web keeps these defaults.
  final double horizontalPadding;
  final double iconSize;

  /// Extra room on the key's leading side, inside the key — the narrow bar's
  /// first key runs under the overhanging level badge, so its content shifts
  /// clear of it while the key still reaches the pill's edge.
  final double leadingInset;
  final double fontSize;

  /// Registers this tracker as a tutorial spotlight target. Shares its id
  /// between the wide cluster and the narrow analytics bar — only one is ever
  /// mounted.
  final String? tutorialTargetId;

  const ClusterTrackerButton({
    required this.indicator,
    required this.count,
    required this.onTap,
    this.selected = false,
    this.segment = TrackerSegment.middle,
    this.axis = Axis.vertical,
    this.horizontalPadding = 16,
    this.leadingInset = 0,
    this.iconSize = 24,
    this.fontSize = 16,
    this.tutorialTargetId,
    super.key,
  });

  @override
  State<ClusterTrackerButton> createState() => _ClusterTrackerButtonState();
}

class _ClusterTrackerButtonState extends State<ClusterTrackerButton> {
  /// The keys tile the pill's whole interior with no gap: outer corners take
  /// the pill's inner radius, shared edges are square.
  static const Radius _outer = Radius.circular(20);
  static const Radius _inner = Radius.zero;
  static const Duration _sinkDuration = Duration(milliseconds: 90);

  ProgressIndicatorEnum get indicator => widget.indicator;
  int get count => widget.count;
  VoidCallback get onTap => widget.onTap;
  bool get selected => widget.selected;
  double get horizontalPadding => widget.horizontalPadding;
  double get iconSize => widget.iconSize;
  double get fontSize => widget.fontSize;

  bool _hovered = false;

  /// A pointer is down on the key: it sinks for the press, like a real key.
  bool _pressed = false;

  BorderRadius get _radius {
    final vertical = widget.axis == Axis.vertical;
    final leading = widget.segment == TrackerSegment.first ? _outer : _inner;
    final trailing = widget.segment == TrackerSegment.last ? _outer : _inner;
    return vertical
        ? BorderRadius.vertical(top: leading, bottom: trailing)
        : BorderRadius.horizontal(left: leading, right: trailing);
  }

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    // While this section has a live background practice session, the tracker
    // wears the practice badge (icon + running timer) and its tap RESUMES the
    // session instead of opening analytics (gated in the view model). See
    // routing.instructions.md § Practice is a persistent background session.
    return TutorialTarget(
      targetId: widget.tutorialTargetId,
      child: ListenableBuilder(
        listenable: PracticeSessionHolder.instance,
        builder: (context, _) {
          final theme = Theme.of(context);
          final holder = PracticeSessionHolder.instance;
          final tracksPractice =
              indicator == ProgressIndicatorEnum.wordsUsed ||
              indicator == ProgressIndicatorEnum.morphsUsed;
          final liveSessionStart =
              tracksPractice && holder.liveType == indicator.constructType
              ? holder.current?.sessionController.session?.startedAt
              : null;
          final live = liveSessionStart != null;

          final semanticsLabel = live
              ? '${indicator.tooltip(context)}: $count — '
                    '${L10n.of(context).practice}'
              : '${indicator.tooltip(context)}: $count';

          final radius = _radius;
          final shape = RoundedRectangleBorder(borderRadius: radius);
          final sunk = _pressed || (selected && !live);

          // The key's face: brighter than the pill field so it stands up off
          // it in both themes. A live practice session paints the face in
          // primary instead — the badge takes the key's place.
          final restFace = live
              ? theme.colorScheme.primary.withValues(
                  alpha: _hovered ? 1.0 : 0.85,
                )
              : _hovered
              ? Color.alphaBlend(
                  theme.colorScheme.onSurface.withAlpha(14),
                  theme.colorScheme.surfaceBright,
                )
              : theme.colorScheme.surfaceBright;
          // Pressed in: below the pill field, so it reads as sitting lower
          // than its neighbours, with the gold of the open panel washed over
          // it and shaded along the top edge where the bezel would cast.
          final sunkFace = live
              ? Color.alphaBlend(Colors.black.withAlpha(50), restFace)
              : Color.alphaBlend(
                  theme.pangea.goldFixedDim.withAlpha(80),
                  Color.alphaBlend(
                    Colors.black.withAlpha(60),
                    theme.colorScheme.surfaceContainer,
                  ),
                );
          final face = sunk ? sunkFace : restFace;
          final well = Color.alphaBlend(
            Colors.black.withAlpha(140),
            theme.colorScheme.surfaceContainer,
          );
          // The open panel's key also lights its icon gold — a graphic, so
          // the 3:1 graphic bar applies, not the text bar the count needs.
          final iconColor = selected && !live ? theme.pangea.goldGraphic : null;

          return Tooltip(
            message: live
                ? L10n.of(context).practice
                : indicator.tooltip(context),
            // The target below carries the full "<stat>: <count>" name;
            // exclude the Tooltip so it isn't announced twice ("Stars Stars: 0").
            excludeFromSemantics: true,
            child: Listener(
              // Pointer-level, so the sink tracks the finger without taking
              // the tap away from the InkWell inside.
              onPointerDown: (_) => _setPressed(true),
              onPointerUp: (_) => _setPressed(false),
              onPointerCancel: (_) => _setPressed(false),
              child: FocusRingTapTarget(
                onTap: onTap,
                shape: shape,
                // The exact count — assistive tech is never given the
                // abbreviation.
                label: semanticsLabel,
                // Inside the key: the keys tile the pill, so outside the
                // edge is a neighbour or the pill's clip.
                ringStrokeAlign: BorderSide.strokeAlignInside,
                onHover: (h) => setState(() => _hovered = h),
                // Hover lightens the face itself; an ink wash would paint
                // under the opaque key and never show.
                hoverColor: Colors.transparent,
                // Fixed outer size so a sinking key never shifts its
                // neighbours: the face drops inside its own well.
                // The key's fixed base: its well, and a hairline all round.
                // Both stay put while the key sinks.
                child: Container(
                  color: well,
                  // Foreground, or the key painted over it would hide it.
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(color: well, width: 1),
                    borderRadius: radius,
                  ),
                  child: AnimatedPadding(
                    duration: _sinkDuration,
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(
                      top: sunk ? ClusterTrackerButton.keyDepth : 0,
                    ),
                    child: AnimatedContainer(
                      duration: _sinkDuration,
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        color: face,

                        // The inset shadow of a pressed key, as a gradient:
                        // BoxShadow cannot paint inside a box.
                        gradient: sunk
                            ? LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.25],
                                colors: [
                                  Color.alphaBlend(
                                    Colors.black.withAlpha(100),
                                    face,
                                  ),
                                  face,
                                ],
                              )
                            : null,
                      ),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding + widget.leadingInset,
                        8,
                        horizontalPadding,
                        8,
                      ),
                      child: live
                          ? PracticeSessionBadge(
                              startedAt: liveSessionStart,
                              iconSize: iconSize,
                              fontSize: fontSize,
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  indicator.icon,
                                  size: iconSize,
                                  color: iconColor,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  compactCount(count),
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    height: 1.1,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The gold level shield overhanging the powerups pill (opens the level tab).
/// Public so [WorldAnalyticsBar] can place it at the bar's left end.
///
/// Unlike the trackers, the medal shows hover and the open Level panel in
/// **its own gold** ([PangeaColors.goldHighlight]) rather than behind
/// itself: the trackers' circular wash sat gold-on-gold under a solid gold
/// shield and read as a stray circle instead of feedback (#8067).
class ClusterLevelMedal extends StatefulWidget {
  final int level;
  final VoidCallback onTap;

  /// Whether the Level analytics tab is open — then the shield stays in its
  /// deepened gold, the sticky counterpart of hover (#7977, #8067).
  final bool selected;

  const ClusterLevelMedal({
    required this.level,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  @override
  State<ClusterLevelMedal> createState() => _ClusterLevelMedalState();
}

class _ClusterLevelMedalState extends State<ClusterLevelMedal> {
  bool _hovered = false;

  /// Room around the shield for the two-tone ring, which sits outside it.
  static const double _ringClearance = 2 * FocusRingTapTarget.ringWidth;

  static Path _shieldOutline(Rect rect) =>
      LevelRibbon.shieldPath(rect.deflate(_ringClearance));

  @override
  Widget build(BuildContext context) {
    final label = '${L10n.of(context).level} ${widget.level}';
    final lit = _hovered || widget.selected;
    return Tooltip(
      message: label,
      // The target names this; exclude the Tooltip to avoid "Level 2 Level 2".
      excludeFromSemantics: true,
      child: FocusRingTapTarget(
        onTap: widget.onTap,
        label: label,
        onHover: (hovered) => setState(() => _hovered = hovered),
        // No wash behind the shield — the shield's own gold carries hover
        // (#8067).
        hoverColor: Colors.transparent,
        // The ring traces the shield rather than circling it (#8067), and is
        // two-tone because it crosses the XP ring and the map, where the gold
        // ring measures 1.0 to 2.9:1 (#9114).
        shape: const PathBorder(outline: _shieldOutline),
        twoToneRing: true,
        ringStrokeAlign: BorderSide.strokeAlignOutside,
        child: Padding(
          padding: const EdgeInsets.all(_ringClearance),
          child: LevelRibbon(
            height: 44,
            level: widget.level,
            color: lit ? Theme.of(context).pangea.goldHighlight : null,
          ),
        ),
      ),
    );
  }
}

/// The active L2 indicator below the powerups pill (Figma `Flags`). Shows the
/// language's flag SVG ([LanguageModel.svgUrl]) when it has a usable locale
/// (e.g. `es-ES` → Spanish flag), with the uppercased language code (e.g. `ES`)
/// overlaid on top for at-a-glance identification. When there is no usable
/// locale, or the SVG fails to load, the code is shown on its own; a white
/// outline keeps it legible over any flag. Gated on
/// [LanguageModel.shouldShowFlag], the same rule the language pickers use.
/// Tapping it opens the learning settings page.
///
/// Public (not `_`-prefixed) and its size overridable so [WorldAnalyticsBar]
/// can reuse it at the "slightly smaller than web" size the mobile chrome
/// calls for (routing.instructions.md, "Single-column analytics nav bar") without
/// duplicating the flag/outline/tooltip logic.
class ClusterLanguageFlag extends StatelessWidget {
  final LanguageModel language;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double fontSize;

  const ClusterLanguageFlag({
    required this.language,
    required this.onTap,
    this.width = _defaultWidth,
    this.height = _defaultHeight,
    this.fontSize = _defaultFontSize,
    super.key,
  });

  static const double _defaultWidth = 52.0;
  static const double _defaultHeight = 36.0;
  static const double _defaultFontSize = 18.0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: l10n.learningSettings,
        // The target below names this (language + settings); exclude the
        // Tooltip so its message isn't appended again.
        excludeFromSemantics: true,
        // InkWell hit-tests its whole rect, so the entire chip is tappable —
        // not just the painted glyphs / flag pixels.
        child: FocusRingTapTarget(
          onTap: onTap,
          // The chip's own outer rounding (its radius + borderWidth).
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          label: '${language.getDisplayName(l10n)}, ${l10n.learningSettings}',
          child: LanguageFlagChip(
            language: language,
            langCode: language.langCode,
            width: width,
            height: height,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}
