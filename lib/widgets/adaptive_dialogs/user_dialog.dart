import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:fluffychat/widgets/users/about_me_display.dart';
import 'package:fluffychat/widgets/users/country_display.dart';
import 'package:fluffychat/widgets/users/level_display_name.dart';
import '../future_loading_dialog.dart';
import '../hover_builder.dart';
import '../matrix.dart';
import '../mxc_image_viewer.dart';

class UserDialog extends StatelessWidget {
  final Profile profile;
  final bool noProfileWarning;
  final Uri uri;

  const UserDialog(
    this.profile, {
    required this.uri,
    this.noProfileWarning = false,
    super.key,
  });

  static Future<void> show({
    required BuildContext context,
    required Profile profile,
    required Uri uri,
    bool noProfileWarning = false,
  }) => showAdaptiveDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) =>
        UserDialog(profile, noProfileWarning: noProfileWarning, uri: uri),
  );

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final dmRoomId = client.getDirectChatFromUserId(profile.userId);
    final displayname =
        profile.displayName ??
        profile.userId.localpart ??
        L10n.of(context).user;

    var copied = false;
    final theme = Theme.of(context);
    final avatar = profile.avatarUrl;

    return AlertDialog.adaptive(
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Center(child: Text(displayname, textAlign: TextAlign.center)),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256, maxHeight: 256),
        child: PresenceBuilder(
          userId: profile.userId,
          client: Matrix.of(context).client,
          builder: (context, presence) {
            if (presence == null) return const SizedBox.shrink();
            final lastActiveTimestamp = presence.lastActiveTimestamp;
            final presenceText = presence.currentlyActive == true
                ? L10n.of(context).currentlyActive
                : lastActiveTimestamp != null
                ? L10n.of(context).lastActiveAgo(
                    lastActiveTimestamp.localizedTimeShort(context),
                  )
                : null;

            return SingleChildScrollView(
              child: Column(
                spacing: 8,
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                children: [
                  HoverBuilder(
                    builder: (context, hovered) => StatefulBuilder(
                      builder: (context, setState) => MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: profile.userId),
                            );
                            setState(() {
                              copied = true;
                            });
                          },
                          child: RichText(
                            text: TextSpan(
                              children: [
                                WidgetSpan(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 4.0),
                                    child: AnimatedScale(
                                      duration: FluffyThemes.animationDuration,
                                      curve: FluffyThemes.animationCurve,
                                      scale: hovered
                                          ? 1.33
                                          : copied
                                          ? 1.25
                                          : 1.0,
                                      child: Icon(
                                        copied
                                            ? Icons.check_circle
                                            : Icons.copy,
                                        size: 12,
                                        color: copied ? Colors.green : null,
                                      ),
                                    ),
                                  ),
                                ),
                                TextSpan(text: profile.userId),
                              ],
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 10,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Avatar(
                      mxContent: avatar,
                      name: displayname,
                      size: Avatar.defaultSize * 2,
                      onTap: avatar != null
                          ? () => showDialog(
                              context: context,
                              builder: (_) => MxcImageViewer(avatar),
                            )
                          : null,
                      userId: profile.userId,
                    ),
                  ),
                  if (presenceText != null)
                    Text(
                      presenceText,
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Column(
                      children: [
                        LevelDisplayName(userId: profile.userId),
                        CountryDisplay(userId: profile.userId),
                        AboutMeDisplay(userId: profile.userId),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        if (client.userID != profile.userId) ...[
          AdaptiveDialogAction(
            borderRadius: AdaptiveDialogAction.topRadius,
            bigButtons: true,
            onPressed: () async {
              final router = GoRouter.of(context);
              final roomIdResult = await showFutureLoadingDialog(
                context: context,
                future: () => client.createPangeaDirectChat(profile.userId),
              );
              final roomId = roomIdResult.result;
              if (roomId == null) return;
              if (context.mounted) Navigator.of(context).pop();
              router.go('/rooms/$roomId');
            },
            child: Text(
              dmRoomId == null
                  ? L10n.of(context).startConversation
                  : L10n.of(context).sendAMessage,
            ),
          ),
          if (profile.userId != BotName.byEnvironment &&
              profile.userId != Environment.supportUserId)
            AdaptiveDialogAction(
              bigButtons: true,
              borderRadius: AdaptiveDialogAction.centerRadius,
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.go(
                  WorkspaceNav.openSettings(
                    uri,
                    page: 'security/ignorelist/${profile.userId}',
                  ),
                );
              },
              child: Text(
                L10n.of(context).block,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
        AdaptiveDialogAction(
          bigButtons: true,
          borderRadius: AdaptiveDialogAction.bottomRadius,
          onPressed: Navigator.of(context).pop,
          child: Text(L10n.of(context).close),
        ),
      ],
    );
  }
}
