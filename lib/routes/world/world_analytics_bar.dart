import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/hex_level_badge.dart';
import 'package:fluffychat/routes/world/level_up_badge_celebration.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model_builder.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/routes/world/xp_border_painter.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

/// The full bar's plain-values rendering, isolated from the Matrix/analytics
/// data plumbing above so it is unit-testable without a live Client: every
/// value it renders (avatar, name, language, tracker counts, level, XP
/// progress) is a plain field, and every tap is a plain callback. Nothing at
/// or below this widget may call `Matrix.of`, `GoRouterState.of`, or
/// `context.go` — values and callbacks only. (The old temporary-expansion
/// state machine — collapsed rendering, ~3s timer, focus suspension — is
/// gone: full-screen surfaces host [AnalyticsHeaderAvatar] in their own app
/// bar instead of a floating collapsed bar.)
class WorldAnalyticsBar extends StatelessWidget {
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

  const WorldAnalyticsBar({this.flagBuilder, super.key});

  static const double expandedHeight = 90.0;

  @override
  Widget build(BuildContext context) => UserClusterViewModelBuilder(
    builder: (context, viewModel) => WorldAnalyticsBarInternal(
      viewModel: viewModel,
      flagBuilder: flagBuilder,
    ),
  );
}

class WorldAnalyticsBarInternal extends StatelessWidget {
  final UserClusterViewModel viewModel;
  final Widget Function(
    LanguageModel language,
    VoidCallback onTap,
    double width,
    double height,
    double fontSize,
  )?
  flagBuilder;

  const WorldAnalyticsBarInternal({
    super.key,
    required this.viewModel,
    required this.flagBuilder,
  });

  static const double _avatarSize = 56.0;

  /// Gap between the pill+badge unit and the avatar column.
  static const double _pillAvatarGap = 12.0;

  // The mobile flag is smaller than web's 52x36, per the Figma bar frame.
  static const double _flagWidth = 40.0;
  static const double _flagHeight = 28.0;
  static const double _flagFontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: viewModel.languageStream,
      builder: (context, _) {
        final l2 = viewModel.userL2;
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
                  child: _PowerupsRow(viewModel: viewModel),
                ),
              ),
              const SizedBox(width: _pillAvatarGap),
              Column(
                mainAxisSize: MainAxisSize.min,
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
                      size: _avatarSize,
                    ),
                  ),
                  if (l2 != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child:
                          flagBuilder?.call(
                            l2,
                            () => viewModel.openLearningSettings(context),
                            _flagWidth,
                            _flagHeight,
                            _flagFontSize,
                          ) ??
                          ClusterLanguageFlag(
                            language: l2,
                            onTap: () =>
                                viewModel.openLearningSettings(context),
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
      },
    );
  }
}

/// The gold powerups pill's three trackers, laid out horizontally instead of
/// the web cluster's vertical stack. Same counts, same tooltip/semantics
/// labels, same shimmer-while-initializing as the cluster's pill, so the two
/// surfaces never disagree — but all values arrive as plain fields.
class _PowerupsRow extends StatelessWidget {
  final UserClusterViewModel viewModel;

  const _PowerupsRow({required this.viewModel});

  static const double _xpStroke = 5.0;
  static const double _innerRadius = 20.0;

  // Pill interior: extra left inset so the trackers clear the hex badge's
  // inner half, tight vertical padding for the compact bar-height pill.
  static const double _pillTrackerClearance = 10.0;
  static const double _pillVerticalPadding = 2.0;
  static const double _pillRightPadding = 14.0;

  /// Half the hex badge's width — how far it sticks out past the pill's
  /// left edge (the Figma overhang).
  static final double _hexBadgeOverhang = _badgeWidth / 2;

  // The bar's hex badge is smaller than [_HexLevelBadge]'s web-facing
  // defaults, per the Figma bar frame.
  static const double _badgeWidth = 42.0;
  static const double _badgeHeight = 36.0;
  static const double _badgeFontSize = 16.0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: viewModel.languageStream,
      builder: (context, _) {
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
                final progress = (derived?.levelProgress ?? 0.0).clamp(
                  0.0,
                  1.0,
                );

                return Stack(
                  alignment: Alignment.centerLeft,
                  // The badge's level-up celebration paints just outside the
                  // pill unit's bounds (pulse + chip); don't clip it. The
                  // celebration is decoration-only (IgnorePointer), so the
                  // hit-test caveat below still only concerns the badge itself.
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: _hexBadgeOverhang),
                      child: CustomPaint(
                        painter: XpBorderPainter(
                          progress: progress,
                          trackColor: const Color.fromARGB(130, 135, 135, 135),
                          progressColor: AppConfig.goldByTheme(context),
                          stroke: _xpStroke,
                          radius: _innerRadius + _xpStroke / 2,
                          anchor: XpBorderAnchor.leftCenter,
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
                            padding: EdgeInsets.fromLTRB(
                              _hexBadgeOverhang + _pillTrackerClearance,
                              _pillVerticalPadding,
                              _pillRightPadding,
                              _pillVerticalPadding,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: Row(
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
                          levelUpdates: viewModel.levelUpdates,
                          child: HexLevelBadge(
                            level: level,
                            onTap: () => viewModel.openLevel(context),
                            width: _badgeWidth,
                            height: _badgeHeight,
                            fontSize: _badgeFontSize,
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
      },
    );
  }
}
