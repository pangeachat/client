import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/svg.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/notifications/notifications_constants.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class SuggestMobileDialog extends StatelessWidget {
  const SuggestMobileDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 24.0,
              ),
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CachedNetworkImage(
                    imageUrl:
                        "${AppConfig.assetsBaseURL}/${NotificationsConstants.notifRequestImage}",
                    errorWidget: (_, _, _) => SizedBox.shrink(),
                  ),
                  Text(
                    l10n.enableNotificationsTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.suggestMobileDesc,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 10.0,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: AppConfig.androidUpdateURL),
                          );
                          Navigator.of(
                            context,
                          ).pop<OkCancelResult>(OkCancelResult.cancel);
                        },
                        child: SvgPicture.asset(
                          "assets/pangea/google.svg",
                          height: 20,
                          width: 20,
                          colorFilter: ColorFilter.mode(
                            Theme.of(context).colorScheme.onPrimaryContainer,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: AppConfig.iosUpdateURL),
                          );
                          Navigator.of(
                            context,
                          ).pop<OkCancelResult>(OkCancelResult.cancel);
                        },
                        child: SvgPicture.asset(
                          "assets/pangea/apple.svg",
                          height: 20,
                          width: 20,
                          colorFilter: ColorFilter.mode(
                            Theme.of(context).colorScheme.onPrimaryContainer,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHigh,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop<OkCancelResult>(OkCancelResult.cancel),
                    child: Wrap(
                      children: [
                        Text(
                          l10n.skipForNow,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(180),
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Close button
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(
                  context,
                ).pop<OkCancelResult>(OkCancelResult.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
