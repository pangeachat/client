import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/support/support_client_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SupportChatListTile extends StatefulWidget {
  const SupportChatListTile({super.key});

  @override
  State<SupportChatListTile> createState() => SupportChatListTileState();
}

class SupportChatListTileState extends State<SupportChatListTile> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final blockedUsers = Matrix.of(context).client.ignoredUsers;
    if (blockedUsers.contains(Environment.supportUserId)) {
      return SizedBox.shrink();
    }

    return ListTile(
      leading: Icon(Icons.help_outline_outlined),
      trailing: const Icon(Icons.chat_bubble_outline),
      title: Text(L10n.of(context).chatWithSupport),
      onTap: _loading
          ? null
          : () async {
              setState(() => _loading = true);
              try {
                final resp = await showFutureLoadingDialog(
                  context: context,
                  future: Matrix.of(context).client.startChatWithSupport,
                );
                if (!mounted) return;
                if (resp.isError) return;
                context.go('/rooms/${resp.result}');
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
    );
  }
}
