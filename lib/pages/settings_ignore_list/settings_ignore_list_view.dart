import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import '../../widgets/matrix.dart';
import 'settings_ignore_list.dart';

class SettingsIgnoreListView extends StatelessWidget {
  final SettingsIgnoreListController controller;

  const SettingsIgnoreListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).blockedUsers),
      ),
      body: MaxWidthBody(
        withScrolling: false,
        child: StreamBuilder(
          stream: client.onSync.stream.where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.ignored_user_list',
                ) ??
                false,
          ),
          builder: (context, asyncSnapshot) {
            // #Pangea
            // if (client.prevBatch == null) {
            //   return const Center(child: CircularProgressIndicator.adaptive());
            // }
            // Pangea#
            return Column(
              mainAxisSize: .min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      // #Pangea
                      ValueListenableBuilder(
                        valueListenable: controller.ignoring,
                        builder: (context, ignoring, _) =>
                            // Pangea#
                            TextField(
                              controller: controller.controller,
                              autocorrect: false,
                              textInputAction: TextInputAction.done,
                              // #Pangea
                              // onSubmitted: (_) =>
                              //     controller.ignoreUser(context),
                              onSubmitted: ignoring
                                  ? null
                                  : (_) => controller.ignoreUser(context),
                              // Pangea#
                              decoration: InputDecoration(
                                errorText: controller.errorText,
                                hintText: '@bad_guy:domain.abc',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                                labelText: L10n.of(context).blockUsername,
                                suffixIcon: IconButton(
                                  tooltip: L10n.of(context).block,
                                  icon: const Icon(Icons.add),
                                  // #Pangea
                                  // onPressed: () =>
                                  //     controller.ignoreUser(context),
                                  onPressed: ignoring
                                      ? null
                                      : () => controller.ignoreUser(context),
                                  // Pangea#
                                ),
                              ),
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        L10n.of(context).blockListDescription,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ],
                  ),
                ),
                Divider(color: theme.dividerColor),
                Expanded(
                  child: ListView.builder(
                    itemCount: client.ignoredUsers.length,
                    itemBuilder: (c, i) => ListTile(
                      title: Text(client.ignoredUsers[i]),
                      trailing: IconButton(
                        tooltip: L10n.of(context).delete,
                        icon: const Icon(Icons.delete_outlined),
                        // #Pangea
                        // onPressed: () => showFutureLoadingDialog(
                        //   context: context,
                        //   future: () =>
                        //       client.unignoreUser(client.ignoredUsers[i]),
                        // ),
                        onPressed: () =>
                            controller.unignoreUser(client.ignoredUsers[i]),
                        // Pangea#
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
