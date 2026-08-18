import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/widgets/decorative_stars.dart';
import 'package:fluffychat/features/subscription/widgets/locked_shimmer_box.dart';
import 'package:fluffychat/features/subscription/widgets/unlock_button.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';

class MessageUnsubscribedCard extends StatelessWidget {
  /// The height the skeleton and the call to action share — enough to read as
  /// the word card it stands in for.
  static const double _bodyHeight = 170.0;

  final PangeaTokenText token;
  final VoidCallback? onClose;

  const MessageUnsubscribedCard({super.key, required this.token, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(maxWidth: AppConfig.toolbarMinWidth),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40.0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                onClose != null
                    ? IconButton(
                        tooltip: L10n.of(context).close,
                        color: theme.iconTheme.color,
                        icon: const Icon(Icons.close),
                        onPressed: onClose,
                      )
                    : const SizedBox(width: 40.0, height: 40.0),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40.0),
                    alignment: Alignment.center,
                    child: SelectableText(
                      token.content,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28.0,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: isDarkMode
                            ? AppConfig.yellowLight
                            : AppConfig.yellowDark,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 40.0, height: 40.0),
              ],
            ),
          ),
          SizedBox(
            height: _bodyHeight,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A skeleton of the real word card: its meaning, the emoji
                // choices, and the example line beneath them.
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 10.0),
                    LockedShimmerBox(width: 200, height: 30),
                    SizedBox(height: 12.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 8.0,
                      children: [
                        LockedShimmerBox(width: 65, height: 65),
                        LockedShimmerBox(width: 65, height: 65),
                        LockedShimmerBox(width: 65, height: 65),
                        LockedShimmerBox(width: 65, height: 65),
                      ],
                    ),
                    SizedBox(height: 12.0),
                    LockedShimmerBox(width: 250, height: 30),
                  ],
                ),
                // Off the corners, unequal insets, unmatched sizes — a matched
                // pair at opposite corners framed the card rather than
                // scattering across it (#7929 review).
                const DecorativeStars(
                  stars: [
                    DecorativeStarSpec(
                      size: 66.0,
                      top: -6.0,
                      left: 22.0,
                      rotation: -0.24,
                    ),
                    DecorativeStarSpec(
                      size: 42.0,
                      top: 104.0,
                      right: 30.0,
                      rotation: 0.5,
                    ),
                  ],
                ),
                UnlockButton(
                  label: L10n.of(context).unlockLearningTools,
                  showStars: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
