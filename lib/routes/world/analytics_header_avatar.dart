import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/circular_xp_ring_painter.dart';
import 'package:fluffychat/routes/world/hex_level_badge.dart';
import 'package:fluffychat/routes/world/level_up_badge_celebration.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model_builder.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';

class AnalyticsHeaderAvatar extends StatelessWidget {
  const AnalyticsHeaderAvatar({super.key});

  @override
  Widget build(BuildContext context) => UserClusterViewModelBuilder(
    builder: (context, viewModel) => Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: AnalyticsHeaderAvatarInternal(
        viewModel: viewModel,
        // App-bar sized: the full-size circle is built for open floating
        // space; at 0.75 the ring + badge + flag fit the toolbar's height.
        scale: 0.75,
      ),
    ),
  );
}

/// The avatar circle wearing the XP ring, the level badge, and the small
/// flag (Figma collapsed component) — one tap target, announced as a single
/// button. Plain values only; [AnalyticsHeaderAvatar] is its Matrix-aware
/// host, mounting it in a full-screen chat's app bar (routing.instructions.md
/// → "Single-column analytics nav bar"). [scale] shrinks the whole cluster
/// proportionally so it fits a toolbar.
class AnalyticsHeaderAvatarInternal extends StatelessWidget {
  final UserClusterViewModel viewModel;
  final double scale;

  const AnalyticsHeaderAvatarInternal({
    required this.viewModel,
    this.scale = 1.0,
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
    final label = L10n.of(context).analyticsAndSettingsLabel;
    return StreamBuilder(
      stream: viewModel.languageStream,
      builder: (context, _) {
        final l2 = viewModel.userL2;
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
              onTap: () => viewModel.openAnalyticsSummary(context),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => viewModel.openAnalyticsSummary(context),
                child: FutureBuilder<DerivedAnalyticsDataModel>(
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
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: Size.square(_avatarSize + 2 * _xpStroke),
                          painter: CircularXpRingPainter(
                            progress: progress,
                            trackColor: const Color.fromARGB(
                              130,
                              135,
                              135,
                              135,
                            ),
                            progressColor: AppConfig.goldByTheme(context),
                            stroke: _xpStroke,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(_xpStroke),
                            child: ListenableBuilder(
                              listenable: Listenable.merge([
                                viewModel.avatarUrl,
                                viewModel.displayName,
                              ]),
                              builder: (context, _) => ClusterAvatar(
                                avatarUrl: viewModel.avatarUrl.value,
                                name: viewModel.displayName.value,
                                onTap: () =>
                                    viewModel.openAnalyticsSummary(context),
                                size: _avatarSize,
                              ),
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
                                levelUpdates: viewModel.levelUpdates,
                                child: HexLevelBadge(
                                  level: level,
                                  onTap: () =>
                                      viewModel.openAnalyticsSummary(context),
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
                                    () =>
                                        viewModel.openAnalyticsSummary(context),
                                    _flagWidth,
                                    _flagHeight,
                                    _flagFontSize,
                                  ) ??
                                  ClusterLanguageFlag(
                                    language: l2,
                                    onTap: () =>
                                        viewModel.openAnalyticsSummary(context),
                                    width: _flagWidth,
                                    height: _flagHeight,
                                    fontSize: _flagFontSize,
                                  ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
