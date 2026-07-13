import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/compact_count.dart';
import 'package:fluffychat/routes/world/level_up_badge_celebration.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model_builder.dart';
import 'package:fluffychat/routes/world/xp_border_painter.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/avatar.dart';
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
  Widget build(BuildContext context) => UserClusterViewModelBuilder(
    builder: (context, viewModel) =>
        WorldUserClusterInternal(viewModel: viewModel),
  );
}

class WorldUserClusterInternal extends StatelessWidget {
  final UserClusterViewModel viewModel;
  const WorldUserClusterInternal({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: viewModel.languageStream,
      builder: (context, _) {
        final l2 = viewModel.userL2;
        return Semantics(
          label: L10n.of(context).analyticsAndSettingsLabel,
          container: true,
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
              _PowerupsPill(viewModel: viewModel),
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
        // The Semantics below already names this control; without this the
        // Tooltip's own message is announced too, doubling the accessible name
        // ("Account Account"). See accessibility.instructions.md.
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          // Expose the tap on the announced node so screen-reader users can
          // activate it (e.g. open Settings); GestureDetector alone leaves the
          // button unactivatable via assistive tech. See issue #7185.
          onTap: onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Avatar(
              mxContent: avatarUrl,
              name: name,
              size: size,
              showPresence: false,
            ),
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
  const _PowerupsPill({required this.viewModel});

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
                // The pill's frame IS the XP ring: a gray track that fills gold clockwise
                // from the bottom-center (where the level medal sits) toward the next
                // level. The trackers sit on a white field inside it; there is no solid
                // gold fill — the only gold is the XP progress.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      painter: XpBorderPainter(
                        progress: progress,
                        trackColor: const Color.fromARGB(130, 135, 135, 135),
                        progressColor: AppConfig.goldByTheme(context),
                        stroke: _xpStroke,
                        radius: _innerRadius + _xpStroke / 2,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(_xpStroke),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(_innerRadius),
                          ),
                          clipBehavior: Clip.antiAlias,
                          padding: EdgeInsets.all(4.0),
                          child: Material(
                            type: MaterialType.transparency,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StreamBuilder(
                                  stream: viewModel.starsUpdateStream,
                                  builder: (context, _) {
                                    final stars = viewModel.starsEarned;
                                    return ClusterTrackerButton(
                                      indicator: ProgressIndicatorEnum.stars,
                                      count: stars,
                                      onTap: () => viewModel.openAnalytics(
                                        context,
                                        AnalyticsPanelTab.sessions,
                                      ),
                                    );
                                  },
                                ),
                                ClusterTrackerButton(
                                  indicator: ProgressIndicatorEnum.morphsUsed,
                                  count: grammar,
                                  onTap: () => viewModel.openAnalytics(
                                    context,
                                    AnalyticsPanelTab.grammar,
                                  ),
                                ),
                                ClusterTrackerButton(
                                  indicator: ProgressIndicatorEnum.wordsUsed,
                                  count: vocab,
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

/// One tracker in the powerups pill: a dark icon over its count, on the white
/// inner field. Tapping opens that metric's analytics tab. Public so
/// [WorldAnalyticsBar] can lay the same three trackers out horizontally.
/// The displayed count abbreviates above 999 ([compactCount]) so the pill
/// never outgrows the allocator's fixed cluster gutter; the semantics label
/// carries the exact count.
class ClusterTrackerButton extends StatelessWidget {
  final ProgressIndicatorEnum indicator;
  final int count;
  final VoidCallback onTap;

  /// Sizing knobs so the narrow analytics bar can render the compact variant
  /// (the Figma mobile pill); web keeps these defaults.
  final double horizontalPadding;
  final double iconSize;
  final double fontSize;

  const ClusterTrackerButton({
    required this.indicator,
    required this.count,
    required this.onTap,
    this.horizontalPadding = 16,
    this.iconSize = 24,
    this.fontSize = 16,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: indicator.tooltip(context),
      // The Semantics below carries the full "<stat>: <count>" name; exclude the
      // Tooltip so it isn't announced twice ("Stars Stars: 0").
      excludeFromSemantics: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppConfig.goldByTheme(context).withAlpha(50),
        borderRadius: BorderRadius.circular(100),
        child: Semantics(
          button: true,
          // The exact count — assistive tech is never given the abbreviation.
          label: '${indicator.tooltip(context)}: $count',
          excludeSemantics: true,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(indicator.icon, size: iconSize),
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
    );
  }
}

/// The gold level shield overhanging the powerups pill (opens the level tab).
/// Public so [WorldAnalyticsBar] can place it at the bar's left end.
class ClusterLevelMedal extends StatelessWidget {
  final int level;
  final VoidCallback onTap;

  const ClusterLevelMedal({
    required this.level,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final label = '${L10n.of(context).level} $level';
    return Tooltip(
      message: label,
      // Semantics below names this; exclude the Tooltip to avoid "Level 2 Level 2".
      excludeFromSemantics: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppConfig.goldByTheme(context).withAlpha(50),
        borderRadius: BorderRadius.circular(100.0),
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          // Expose the tap on the announced node for assistive tech (#7185).
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: LevelRibbon(height: 44, level: level),
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
  static const double _radius = 6.0;
  static const double _borderWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    final outlinedText = Stack(
      children: <Widget>[
        Text(
          language.langCodeShort.toUpperCase(),
          style: TextStyle(
            fontSize: fontSize,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = Colors.white,
          ),
        ),
        Text(
          language.langCodeShort.toUpperCase(),
          style: TextStyle(fontSize: fontSize, color: Colors.black),
        ),
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: l10n.learningSettings,
        // Semantics below names this (language + settings); exclude the Tooltip
        // so its message isn't appended again.
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: '${language.getDisplayName(l10n)}, ${l10n.learningSettings}',
          excludeSemantics: true,
          // Expose the tap on the announced node for assistive tech (#7185).
          onTap: onTap,
          // Opaque so the whole chip is tappable — not just the painted glyphs
          // / flag pixels (a transparent-interior box defers the hit test).
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: width,
              height: height,
              padding: .all(_borderWidth),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(_radius + _borderWidth),
              ),
              child: language.shouldShowFlag
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(_radius),
                      child: Stack(
                        children: [
                          SvgPicture.network(
                            language.svgUrl.toString(),
                            width: width,
                            height: height,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, _, _) => outlinedText,
                            placeholderBuilder: (_) =>
                                SizedBox(width: width, height: height),
                          ),
                          Positioned(child: Center(child: outlinedText)),
                        ],
                      ),
                    )
                  : outlinedText,
            ),
          ),
        ),
      ),
    );
  }
}
