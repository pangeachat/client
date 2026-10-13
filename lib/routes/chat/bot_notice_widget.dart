import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/bot/bot_event_extension.dart';
import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// A notice in the bot DM, shown as a plain message from the bot, with an
/// Open button when it names a place (notices.instructions.md).
class BotNoticeWidget extends StatelessWidget {
  final Event event;

  const BotNoticeWidget(this.event, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDestination = event.hasNoticeDestination;
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: FluffyThemes.maxTimelineWidth,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(
              userId: event.senderId,
              name: event.senderFromMemoryOrFallback.calcDisplayname(),
            ),
            const SizedBox(width: 8.0),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: FluffyThemes.columnWidth * 1.5,
                ),
                padding: EdgeInsets.fromLTRB(
                  16.0,
                  8.0,
                  16.0,
                  hasDestination ? 12.0 : 8.0,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8.0,
                  children: [
                    Text(
                      event.noticeBody ?? '',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: AppConfig.messageFontSize,
                      ),
                    ),
                    if (hasDestination)
                      FilledButton.tonalIcon(
                        onPressed: () => NotificationTapUtil.openNotice(
                          event,
                          GoRouter.of(context),
                        ),
                        icon: const Icon(Icons.arrow_forward),
                        iconAlignment: IconAlignment.end,
                        label: Text(L10n.of(context).open),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
