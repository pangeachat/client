import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/archive/archive.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';

class ArchiveView extends StatelessWidget {
  final ArchiveController controller;
  final Widget? closeButton;

  const ArchiveView(this.controller, {super.key, this.closeButton});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Room>>(
      future: controller.getArchive(context),
      builder: (BuildContext context, snapshot) => Scaffold(
        appBar: AppBar(
          leading: closeButton ?? const Center(child: BackButton()),
          titleSpacing: 0,
          title: Text(
            L10n.of(context).archive,
            style: FluffyThemes.isColumnMode(context)
                ? theme.textTheme.titleLarge
                : theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
          actions: [
            if (snapshot.data?.isNotEmpty ?? false)
              TextButton.icon(
                onPressed: controller.forgetAllAction,
                label: Text(L10n.of(context).clearArchive),
                icon: const Icon(Icons.cleaning_services_outlined),
              ),
          ],
          centerTitle: false,
        ),
        body: MaxWidthBody(
          withScrolling: false,
          child: Builder(
            builder: (BuildContext context) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    L10n.of(context).oopsSomethingWentWrong,
                    textAlign: TextAlign.center,
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                );
              } else {
                if (controller.archive.isEmpty) {
                  return const Center(
                    child: Icon(Icons.archive_outlined, size: 80),
                  );
                }
                return ListView.builder(
                  itemCount: controller.archive.length,
                  itemBuilder: (BuildContext context, int i) => ChatListItem(
                    controller.archive[i],
                    onForget: () => controller.forgetRoomAction(i),
                    onTap: () => context.go(
                      WorkspaceNav.openArchivedRoom(
                        GoRouterState.of(context).uri,
                        controller.archive[i].id,
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
