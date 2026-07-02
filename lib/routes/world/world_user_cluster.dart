import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
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
import 'package:fluffychat/routes/world/xp_border_painter.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

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
class WorldUserCluster extends StatefulWidget {
  const WorldUserCluster({super.key});

  @override
  State<WorldUserCluster> createState() => _WorldUserClusterState();
}

class _WorldUserClusterState extends State<WorldUserCluster> {
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

  /// Open the right-docked analytics panel on [tab]'s summary by writing the
  /// `?right=analytics:<tab>` token (the URL is the source of truth for open
  /// panels). `setRight` replaces the whole right list, so switching trackers
  /// lands on the new tab's summary and drops any open construct detail.
  void _openAnalytics(AnalyticsPanelTab tab) => context.go(
    WorkspaceNav.setRight(GoRouterState.of(context).uri, [
      PanelToken('analytics', tab.name),
    ]),
  );

  /// Open the profile + settings panel on the right (its menu), keeping any
  /// other open panels — world_v2 moved settings/profile to the right column.
  void _openProfile() =>
      context.go(WorkspaceNav.openSettings(GoRouterState.of(context).uri));

  /// The level medal opens the level analytics tab on the right.
  void _openLevel() => context.go(
    WorkspaceNav.setRight(GoRouterState.of(context).uri, [
      const PanelToken('analytics', 'level'),
    ]),
  );

  /// The L2 flag opens the learning settings page on the right directly.
  void _openLearningSettings() => context.go(
    WorkspaceNav.openSettings(GoRouterState.of(context).uri, page: 'learning'),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: MatrixState.pangeaController.userController.languageStream.stream,
      builder: (context, _) {
        final l2 = MatrixState.pangeaController.userController.userL2;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([_avatarUrl, _displayName]),
              builder: (context, _) => _Avatar(
                avatarUrl: _avatarUrl.value,
                name: _displayName.value,
                onTap: _openProfile,
              ),
            ),
            const SizedBox(height: 8),
            _PowerupsPill(
              onTap: _openAnalytics,
              onLevelTap: _openLevel,
              l2: l2,
            ),
            if (l2 != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: _LanguageFlag(
                  language: l2,
                  onTap: _openLearningSettings,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The circular user avatar at the top of the cluster. Opens profile/settings.
class _Avatar extends StatelessWidget {
  final Uri? avatarUrl;
  final String? name;
  final VoidCallback onTap;

  const _Avatar({
    required this.avatarUrl,
    required this.name,
    required this.onTap,
  });

  static const double _size = 56.0;

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
              size: _size,
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
  final void Function(AnalyticsPanelTab) onTap;
  final VoidCallback onLevelTap;
  final LanguageModel? l2;

  const _PowerupsPill({
    required this.onTap,
    required this.onLevelTap,
    required this.l2,
  });

  static const double _xpStroke = 5.0;
  static const double _innerRadius = 20.0;

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final service = matrix.analyticsDataService;
    final l2 = this.l2;

    return StreamBuilder(
      stream: service.updateDispatcher.constructUpdateStream.stream,
      builder: (context, _) {
        final vocab = service.numConstructs(ConstructTypeEnum.vocab);
        final grammar = service.numConstructs(ConstructTypeEnum.morph);

        final content = FutureBuilder<DerivedAnalyticsDataModel>(
          future: l2 != null
              ? service.derivedData(l2.langCodeShort)
              : Future.value(DerivedAnalyticsDataModel()),
          builder: (context, snapshot) {
            final derived = snapshot.data ?? service.cachedDerivedData;
            final level = derived?.level ?? 1;
            final progress = (derived?.levelProgress ?? 0.0).clamp(0.0, 1.0);

            return Stack(
              alignment: Alignment.bottomCenter,
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
                        progressColor: AppConfig.gold,
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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StreamBuilder(
                                stream: client.onRoomState.stream.where(
                                  (e) =>
                                      e.state.type ==
                                      PangeaEventTypes.orchestratorAwardedGoals,
                                ),
                                builder: (context, _) {
                                  final stars = l2 != null
                                      ? client.totalStarsEarned(l2)
                                      : 0;

                                  return _TrackerButton(
                                    indicator: ProgressIndicatorEnum.stars,
                                    count: stars,
                                    onTap: () =>
                                        onTap(AnalyticsPanelTab.sessions),
                                  );
                                },
                              ),
                              _TrackerButton(
                                indicator: ProgressIndicatorEnum.morphsUsed,
                                count: grammar,
                                onTap: () => onTap(AnalyticsPanelTab.grammar),
                              ),
                              _TrackerButton(
                                indicator: ProgressIndicatorEnum.wordsUsed,
                                count: vocab,
                                onTap: () => onTap(AnalyticsPanelTab.vocab),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 30),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  child: _LevelMedal(level: level, onTap: onLevelTap),
                ),
              ],
            );
          },
        );

        return service.isInitializing
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
/// inner field. Tapping opens that metric's analytics tab.
class _TrackerButton extends StatelessWidget {
  final ProgressIndicatorEnum indicator;
  final int count;
  final VoidCallback onTap;

  const _TrackerButton({
    required this.indicator,
    required this.count,
    required this.onTap,
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
        borderRadius: BorderRadius.circular(14),
        child: Semantics(
          button: true,
          label: '${indicator.tooltip(context)}: $count',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(indicator.icon, size: 24),
                const SizedBox(height: 3),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 16,
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
class _LevelMedal extends StatelessWidget {
  final int level;
  final VoidCallback onTap;

  const _LevelMedal({required this.level, required this.onTap});

  // The outer shield shape from Figma (icon/warning-secondary fill #F3C141 ==
  // AppConfig.goldMedal); the level number is overlaid.
  static const String _shieldSvg =
      '<svg viewBox="0 0 24.6667 28.875" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4.33333 28.875V17.5656L0 10.3125L6.16667 0H18.5L24.6667 '
      '10.3125L20.3333 17.5656V28.875L12.3333 26.125L4.33333 28.875Z" '
      'fill="#FDBF01"/></svg>';

  @override
  Widget build(BuildContext context) {
    final label = '${L10n.of(context).level} $level';
    return Tooltip(
      message: label,
      // Semantics below names this; exclude the Tooltip to avoid "Level 2 Level 2".
      excludeFromSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            // Expose the tap on the announced node for assistive tech (#7185).
            onTap: onTap,
            child: SizedBox(
              width: 38,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SvgPicture.string(
                    _shieldSvg,
                    width: 38,
                    height: 44,
                    fit: BoxFit.contain,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '$level',
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
class _LanguageFlag extends StatelessWidget {
  final LanguageModel language;
  final VoidCallback onTap;

  const _LanguageFlag({required this.language, required this.onTap});

  static const double _w = 52.0;
  static const double _h = 36.0;
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
            fontSize: 18,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = Colors.white,
          ),
        ),
        Text(
          language.langCodeShort.toUpperCase(),
          style: TextStyle(fontSize: 18, color: Colors.black),
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
              width: _w,
              height: _h,
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
                            width: _w,
                            height: _h,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, _, _) => outlinedText,
                            placeholderBuilder: (_) =>
                                const SizedBox(width: _w, height: _h),
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
