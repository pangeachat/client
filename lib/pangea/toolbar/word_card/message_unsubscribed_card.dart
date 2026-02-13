import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_box.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MessageUnsubscribedCard extends StatelessWidget {
  final PangeaTokenText token;
  final VoidCallback? onClose;

  const MessageUnsubscribedCard({super.key, required this.token, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final placeholderColor = isDarkMode
        ? Colors.white.withAlpha(50)
        : Colors.black.withAlpha(50);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(maxWidth: AppConfig.toolbarMinWidth),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Positioned(
            top: 50.0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShimmerBox(
                  baseColor: placeholderColor,
                  highlightColor: primaryColor,
                  width: 200,
                  height: 30,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                    (index) => Padding(
                      padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
                      child: ShimmerBox(
                        baseColor: placeholderColor,
                        highlightColor: primaryColor,
                        width: 65,
                        height: 65,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ShimmerBox(
                  baseColor: placeholderColor,
                  highlightColor: primaryColor,
                  width: 250,
                  height: 30,
                ),
              ],
            ),
          ),
          Column(
            children: [
              SizedBox(
                height: 40.0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    onClose != null
                        ? IconButton(
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
                width: double.infinity,
                height: 170.0,
                child: Center(
                  child: PressableButton(
                    borderRadius: BorderRadius.circular(36),
                    color: primaryColor,
                    onPressed: () {
                      MatrixState.pangeaController.subscriptionController
                          .showPaywall(context);
                    },
                    builder: (context, depressed, shadowColor) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: depressed ? shadowColor : primaryColor,
                        borderRadius: BorderRadius.circular(36),
                      ),
                      child: Text(
                        L10n.of(context).unlockLearningTools,
                        style: TextStyle(
                          fontSize: 20.0,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
