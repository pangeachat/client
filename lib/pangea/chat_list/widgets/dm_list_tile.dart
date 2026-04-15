import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/chat_settings/utils/bot_client_extension.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/support/support_client_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class DMListTile extends StatefulWidget {
  final bool visible;
  const DMListTile({super.key, this.visible = true});

  @override
  State<DMListTile> createState() => DMListTileState();
}

class DMListTileState extends State<DMListTile> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final blockedUsers = Matrix.of(context).client.ignoredUsers;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!Matrix.of(context).client.hasBotDM &&
            widget.visible &&
            !blockedUsers.contains(BotName.byEnvironment))
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
                trailing: Icon(Icons.chat_bubble_outline),
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
                          context.go('/rooms/${resp.result}');
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
              ),
            ),
          ),
        if (!Matrix.of(context).client.hasSupportDM &&
            !InstructionsEnum.dismissSupportChat.isToggledOff &&
            widget.visible &&
            !blockedUsers.contains(Environment.supportUserId))
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
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      InstructionsEnum.dismissSupportChat.setToggledOff(true),
                ),
                title: Text(L10n.of(context).chatWithSupport),
                subtitle: Text(L10n.of(context).supportSubtitle),
                onTap: _loading
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        try {
                          final resp = await showFutureLoadingDialog<String>(
                            context: context,
                            future: Matrix.of(
                              context,
                            ).client.startChatWithSupport,
                          );
                          if (!mounted) return;
                          if (resp.isError) return;
                          context.go('/rooms/${resp.result}');
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
              ),
            ),
          ),
      ],
    );
  }
}
