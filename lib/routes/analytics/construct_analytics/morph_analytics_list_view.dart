import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics_data/widgets/analytics_future_builder.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/morph_features_and_tags.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/dotted_border_painter.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MorphAnalyticsListView extends StatelessWidget {
  final ConstructAnalyticsViewState controller;

  const MorphAnalyticsListView({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    // The rows' chips are ONE Tab stop for the whole page, with the arrow keys
    // moving chip to chip in reading order across the feature rows (#8935).
    // A feature the list skips contributes no ids.
    final visibleFeatures = l2 == null
        ? const <MorphFeatureTags>[]
        : controller.morphs.features.where((f) => f.tags.isNotEmpty);

    return Column(
      children: [
        Expanded(
          child: RovingFocusGroup(
            ids: [
              for (final feature in visibleFeatures)
                for (final id in feature.constructIds) id.storageKey,
            ],
            child: CustomScrollView(
              key: const PageStorageKey<String>('morph-analytics'),
              slivers: [
                // Its own padding, so the gap collapses with it on dismissal.
                const SliverToBoxAdapter(
                  child: InstructionsInlineTooltip(
                    instructionsEnum: InstructionsEnum.morphAnalyticsList,
                    padding: EdgeInsets.only(bottom: 16.0),
                  ),
                ),

                // Morph feature boxes
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final feature = controller.morphs.features[index];
                    return feature.tags.isNotEmpty && l2 != null
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: MorphFeatureBox(
                              featureTags: feature,
                              language: l2,
                            ),
                          )
                        : const SizedBox.shrink();
                  }, childCount: controller.morphs.features.length),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MorphFeatureBox extends StatelessWidget {
  final MorphFeatureTags featureTags;
  final String language;

  const MorphFeatureBox({
    super.key,
    required this.featureTags,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final feature = featureTags.feature;
    final tags = featureTags.tags;

    final featureEnum = MorphFeaturesEnum.fromString(feature.value);
    final analyticsService = Matrix.of(context).analyticsDataService;
    final tagIds = featureTags.constructIds;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 16.0,
            children: [
              SizedBox(
                height: 30.0,
                width: 30.0,
                child: MorphIcon(feature: featureEnum),
              ),
              Flexible(
                child: Text(
                  feature.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          // One batched read for every tag of this feature, re-issued only
          // when analytics change — not per rebuild (#8433).
          AnalyticsFutureBuilder<Map<ConstructIdentifier, ConstructUses>>(
            dependencies: [
              feature.value,
              language,
              ...tags.map((tag) => tag.value),
            ],
            fetch: () => analyticsService.getConstructUses(tagIds, language),
            builder: (context, snapshot) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12.0,
                    runSpacing: 12.0,
                    children: [
                      for (var i = 0; i < tags.length; i++)
                        MorphTagChip(
                          feature: featureEnum,
                          tag: tags[i],
                          rovingId: tagIds[i].storageKey,
                          constructAnalytics: snapshot.data?[tagIds[i]],
                          onTap: () {
                            AnalyticsNavigationUtil.navigateToAnalytics(
                              context: context,
                              view: ProgressIndicatorEnum.morphsUsed,
                              construct: tagIds[i],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MorphTagChip extends StatelessWidget {
  final MorphFeaturesEnum feature;
  final GrammarTag tag;
  final ConstructUses? constructAnalytics;
  final VoidCallback onTap;

  /// This chip's id in the enclosing [RovingFocusGroup]: the grammar page's
  /// chips are one Tab stop, with the arrow keys moving between them across
  /// the feature rows (#8935). Null for a chip outside a group.
  final String? rovingId;

  /// Tighter than [AppConfig.borderRadius], which on a chip this short is a
  /// full pill (#9149).
  static const double cornerRadius = 12.0;
  static const double minHeight = 40.0;
  static const double iconBadgeSize = 28.0;

  /// The stage colour as a wash, the same low alpha the vocab filter's
  /// selected ring uses, and the stronger alpha of the edge around it.
  static const int washAlpha = 50;
  static const int borderAlpha = 140;

  /// A locked chip's label and lock: the muted ink pulled a fifth of the way
  /// to the surface, so a locked chip sits behind the unlocked ones and
  /// still clears 4.5:1 in both themes.
  static Color lockedInk(ThemeData theme) => Color.lerp(
    theme.colorScheme.onSurfaceVariant,
    theme.colorScheme.surface,
    0.2,
  )!;

  const MorphTagChip({
    super.key,
    required this.feature,
    required this.tag,
    required this.constructAnalytics,
    required this.onTap,
    this.rovingId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rovingId = this.rovingId;
    final focusNode = rovingId == null
        ? null
        : RovingFocusGroup.nodeOf(context, rovingId);

    final unlocked =
        constructAnalytics != null && constructAnalytics!.numTotalUses > 0 ||
        Matrix.of(context).client.userID == Environment.supportUserId;

    final stageColor =
        (constructAnalytics?.lemmaCategory ?? ConstructLevelEnum.seeds).color(
          context,
        );
    final ink = unlocked ? theme.colorScheme.onSurface : lockedInk(theme);
    final radius = BorderRadius.circular(cornerRadius);
    final shape = RoundedRectangleBorder(borderRadius: radius);

    // The fill and edge belong to the Material, so the InkWell's hover and
    // press ink paints over them instead of under an opaque child.
    return Material(
      color: unlocked ? stageColor.withAlpha(washAlpha) : Colors.transparent,
      shape: unlocked
          ? shape.copyWith(
              side: BorderSide(color: stageColor.withAlpha(borderAlpha)),
            )
          : shape,
      child: FocusRingTapTarget(
        onTap: onTap,
        focusNode: focusNode,
        shape: shape,
        // The seeds wash is gold too, so the gold ring goes around the chip.
        ringStrokeAlign: BorderSide.strokeAlignOutside,
        child: CustomPaint(
          // Locked is an empty slot: no fill, a dashed edge.
          painter: unlocked
              ? null
              : DottedBorderPainter(
                  color: theme.colorScheme.outline,
                  strokeWidth: 1.0,
                  borderRadius: radius,
                ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                6.0,
                6.0,
                12.0,
                6.0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8.0,
                children: [
                  unlocked
                      ? Container(
                          width: iconBadgeSize,
                          height: iconBadgeSize,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6.0),
                          child: MorphIcon(
                            feature: feature,
                            tag: tag.value,
                            size: const Size(16.0, 16.0),
                          ),
                        )
                      : SizedBox.square(
                          dimension: iconBadgeSize,
                          child: Icon(Icons.lock, color: ink, size: 20.0),
                        ),

                  Flexible(
                    child: Text(
                      tag.title,
                      style: TextStyle(fontWeight: FontWeight.bold, color: ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
