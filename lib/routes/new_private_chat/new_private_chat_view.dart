import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/user/widgets/user_filter_chip_row.dart';
import 'package:fluffychat/features/user/widgets/user_result_tile.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/routes/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

class NewPrivateChatView extends StatelessWidget {
  final NewPrivateChatController controller;
  final Widget? closeButton;

  const NewPrivateChatView(this.controller, {super.key, this.closeButton});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final userId = Matrix.of(context).client.userID;

    // The panel's one named group comes from the dispatcher (#8729) — a
    // second full-panel container here was a nameless-to-navigate layer that
    // broke VO's escape-from-group.
    return Scaffold(
      appBar: AppBar(
        leading: closeButton,
        titleSpacing: 0,
        title: ExcludeSemantics(
          child: Text(
            l10n.newDirectMessage,
            style: FluffyThemes.isColumnMode(context)
                ? theme.textTheme.titleLarge
                : theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ),
        centerTitle: false,
      ),
      body: MaxWidthBody(
        withScrolling: false,
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          spacing: 12.0,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: PangeaSearchBar(
                controller: controller.controller,
                onChanged: controller.searchUsers,
                labelText: l10n.searchUsersHint,
                suffixIcon: controller.controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.clear,
                        icon: const Icon(Icons.clear_outlined),
                        onPressed: () {
                          controller.controller.clear();
                          controller.searchUsers();
                        },
                      ),
                prefixIcon: controller.directorySearch.loading
                    ? const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 1,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: UserFilterChipRow(
                chips: [
                  UserFilterChip(
                    label: l10n.myContacts,
                    selected: controller.filter == NewChatFilter.contacts,
                    onSelected: () =>
                        controller.setFilter(NewChatFilter.contacts),
                  ),
                  UserFilterChip(
                    label: l10n.public,
                    selected: controller.filter == NewChatFilter.public,
                    onSelected: () =>
                        controller.setFilter(NewChatFilter.public),
                  ),
                ],
              ),
            ),
            Expanded(
              // No Semantics container here: the panel's one named group
              // comes from the dispatcher (#8729), and a nested container
              // inside it broke VO's escape-from-group (popping from the
              // results jumped to the page root, like the other legacy
              // per-view wrappers this branch removed).
              child: AnimatedSwitcher(
                duration: FluffyThemes.animationDuration,
                child: controller.filter == NewChatFilter.contacts
                    ? _ContactResults(controller)
                    : _PublicResults(controller),
              ),
            ),
            if (userId != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18.0,
                  vertical: 12.0,
                ),
                child: Semantics(
                  label: "${l10n.yourGlobalUserIdIs} $userId",
                  container: true,
                  child: SelectableText.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: l10n.yourGlobalUserIdIs),
                        TextSpan(
                          text: userId,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The people the user already direct-chats with, filtered locally as they
/// type. The share-invite-link row closes the list, so the panel's original
/// way of reaching someone who has no account survives the filter split.
class _ContactResults extends StatelessWidget {
  final NewPrivateChatController controller;

  const _ContactResults(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final contacts = controller.contacts;

    return ListView.builder(
      itemCount: contacts.length + 1,
      itemBuilder: (context, i) {
        if (i == contacts.length) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              foregroundColor: theme.colorScheme.onSecondaryContainer,
              child: Icon(Icons.adaptive.share_outlined),
            ),
            title: Text(l10n.shareInviteLink),
            onTap: controller.inviteAction,
          );
        }

        final contact = contacts[i];
        final profile = Profile(
          avatarUrl: contact.avatarUrl,
          displayName:
              localizedPangeaUserName(contact.id, l10n) ??
              contact.displayName ??
              contact.id.localpart ??
              l10n.user,
          userId: contact.id,
        );
        return UserResultTile(
          profile: profile,
          onTap: () => controller.openUserModal(profile),
        );
      },
    );
  }
}

/// Public directory results for what is typed.
class _PublicResults extends StatelessWidget {
  final NewPrivateChatController controller;

  const _PublicResults(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final search = controller.directorySearch;

    // A failure only takes over the panel when there is nothing to show; a
    // rate-limited keystroke mid-typing leaves the previous results standing.
    final error = search.error;
    if (error != null && search.results.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            error.toLocalizedString(context),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.retrySearch,
            icon: const Icon(Icons.refresh_outlined),
            label: Text(l10n.tryAgain),
          ),
        ],
      );
    }

    if (search.results.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_outlined, size: 86),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              // Before a search has come back, the panel says what to do
              // rather than claiming nobody matches.
              search.lastSearch == null
                  ? l10n.searchUsersHint
                  : l10n.emptyInviteSearchHint,
              style: TextStyle(color: theme.colorScheme.primary),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      itemCount: search.results.length,
      itemBuilder: (context, i) {
        final profile = search.results[i];
        return UserResultTile(
          profile: profile,
          onTap: () => controller.openUserModal(profile),
        );
      },
    );
  }
}
