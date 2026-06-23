import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/chat/chat_banner_builder.dart';
import 'package:fluffychat/routes/chat/icon_rain.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class UnlockedMorphBanner extends StatefulWidget {
  final ConstructIdentifier construct;
  final String overlayKey;
  final Completer<void> closeCompleter;

  const UnlockedMorphBanner({
    super.key,
    required this.construct,
    required this.overlayKey,
    required this.closeCompleter,
  });

  @override
  State<UnlockedMorphBanner> createState() => UnlockedMorphBannerState();
}

class UnlockedMorphBannerState extends State<UnlockedMorphBanner> {
  void _showDetails() {
    AnalyticsNavigationUtil.navigateToAnalytics(
      context: context,
      view: ProgressIndicatorEnum.morphsUsed,
      construct: widget.construct,
    );
  }

  void _showIconRain() {
    if (!mounted) return;
    final feature = MorphFeaturesEnum.fromString(widget.construct.category);
    final tag = widget.construct.lemma;
    OverlayUtil.showOverlay(
      overlayKey: "${widget.construct.string}_points",
      followerAnchor: Alignment.topCenter,
      targetAnchor: Alignment.topCenter,
      context: context,
      child: IconRain(
        addStars: true,
        icon: MorphIcon(size: const Size(8, 8), feature: feature, tag: tag),
      ),
      transformTargetId: "${widget.construct.string}_notification",
      closePrevOverlay: false,
      backDropToDismiss: false,
      ignorePointer: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);

    final feature = widget.construct.category;
    final tag = widget.construct.lemma;
    final copy = GrammarConstructsProvider.getTagTitle(
      feature: feature,
      tag: tag,
    );

    final featureEnum = MorphFeaturesEnum.fromString(feature);

    return CompositedTransformTarget(
      link: MatrixState.pAnyState
          .layerLinkAndKey("${widget.construct.string}_notification")
          .link,
      child: ChatBannerBuilder(
        overlayKey: widget.overlayKey,
        closeCompleter: widget.closeCompleter,
        onTap: _showDetails,
        onAnimatedIn: _showIconRain,
        builder: (context, constraints, close) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(width: constraints.maxWidth >= 600 ? 120.0 : 65.0),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isColumnMode ? 16.0 : 8.0,
                ),
                child: Wrap(
                  spacing: 16.0,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      copy ?? widget.construct.lemma,
                      style: TextStyle(
                        fontSize: FluffyThemes.isColumnMode(context)
                            ? 22.0
                            : 16.0,
                        color: AppConfig.gold,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    MorphIcon(
                      size: isColumnMode ? null : const Size(22.0, 22.0),
                      feature: featureEnum,
                      tag: widget.construct.lemma,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: constraints.maxWidth >= 600 ? 120.0 : 65.0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Tooltip(
                    message: L10n.of(context).details,
                    child: constraints.maxWidth >= 600
                        ? ElevatedButton(
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                                horizontal: 16.0,
                              ),
                            ),
                            onPressed: _showDetails,
                            child: Text(L10n.of(context).details),
                          )
                        : SizedBox(
                            width: 32.0,
                            height: 32.0,
                            child: Center(
                              child: IconButton(
                                tooltip: L10n.of(context).details,
                                icon: const Icon(Icons.info_outline),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(4.0),
                                ),
                                onPressed: _showDetails,
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ),
                  ),
                  SizedBox(
                    width: 32.0,
                    height: 32.0,
                    child: Center(
                      child: Tooltip(
                        message: L10n.of(context).close,
                        child: IconButton(
                          tooltip: L10n.of(context).close,
                          icon: const Icon(Icons.close),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(4.0),
                          ),
                          onPressed: close,
                          constraints: const BoxConstraints(),
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
