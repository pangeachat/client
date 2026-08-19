import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/bot/bot_client_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/support/support_client_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class DMListTile extends StatefulWidget {
  final bool visible;
  const DMListTile({super.key, this.visible = true});

  /// Whether the "Direct message Pangea Bot" tile renders for [client]: no bot
  /// DM yet and the bot not blocked.
  static bool showsBotTile(Client client) =>
      !client.hasBotDM && !client.ignoredUsers.contains(BotName.byEnvironment);

  /// Whether the "Chat with Support" tile renders for [client]: no support DM
  /// yet, not dismissed, and the support account not blocked.
  static bool showsSupportTile(Client client) =>
      !client.hasSupportDM &&
      !InstructionsEnum.dismissSupportChat.isToggledOff &&
      !client.ignoredUsers.contains(Environment.supportUserId);

  /// How many tiles render for [client] — what the mobile chats sheet's
  /// content-fit estimate counts alongside the chat rows, since these tiles
  /// take a row each without being rooms.
  static int tileCount(Client client) =>
      (showsBotTile(client) ? 1 : 0) + (showsSupportTile(client) ? 1 : 0);

  @override
  State<DMListTile> createState() => DMListTileState();
}

class DMListTileState extends State<DMListTile> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.visible && DMListTile.showsBotTile(client))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Material(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              clipBehavior: Clip.hardEdge,
              child: ListTile(
                leading: BotFace(
                  expression: BotExpression.idle,
                  width: Avatar.defaultSize,
                ),
                title: Text(L10n.of(context).directMessageBotTitle),
                subtitle: Text(L10n.of(context).directMessageBotDesc),
                onTap: _loading
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        try {
                          final resp = await showFutureLoadingDialog<String>(
                            context: context,
                            future: Matrix.of(context).client.startChatWithBot,
                          );
                          if (!mounted) return;
                          if (resp.isError) return;
                          context.go(
                            WorkspaceNav.openRoomById(
                              GoRouterState.of(context).uri,
                              resp.result!,
                            ),
                          );
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                ),
              ),
            ),
          ),
        if (widget.visible && DMListTile.showsSupportTile(client))
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Material(
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  clipBehavior: Clip.hardEdge,
                  child: ListTile(
                    contentPadding: EdgeInsets.only(left: 16, right: 16),
                    leading: Container(
                      alignment: Alignment.center,
                      height: Avatar.defaultSize,
                      width: Avatar.defaultSize,
                      child: const Icon(
                        Symbols.chat_add_on,
                        size: Avatar.defaultSize - 16,
                      ),
                    ),
                    title: Text(L10n.of(context).chatWithSupport),
                    subtitle: Text(L10n.of(context).supportSubtitle),
                    onTap: _loading
                        ? null
                        : () async {
                            setState(() => _loading = true);
                            try {
                              final resp =
                                  await showFutureLoadingDialog<String>(
                                    context: context,
                                    future: Matrix.of(
                                      context,
                                    ).client.startChatWithSupport,
                                  );
                              if (!mounted) return;
                              if (resp.isError) return;
                              context.go(
                                WorkspaceNav.openRoomById(
                                  GoRouterState.of(context).uri,
                                  resp.result!,
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => _loading = false);
                            }
                          },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 14,
                child: IconButton.filledTonal(
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: L10n.of(context).dismiss,
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () {
                    InstructionsEnum.dismissSupportChat.setToggledOff(true);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}
