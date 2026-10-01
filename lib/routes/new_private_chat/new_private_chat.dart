import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/direct_chat_contacts_extension.dart';
import 'package:fluffychat/features/user/user_directory_search.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';

/// Which set of people the panel is searching. The invite page's own filters
/// are room-scoped and mean nothing here, so this panel carries just the two
/// that do (#9009).
enum NewChatFilter { contacts, public }

class NewPrivateChat extends StatefulWidget {
  final Widget? closeButton;

  const NewPrivateChat({super.key, this.closeButton});

  @override
  NewPrivateChatController createState() => NewPrivateChatController();
}

class NewPrivateChatController extends State<NewPrivateChat> {
  final TextEditingController controller = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();

  late final UserDirectorySearch directorySearch;

  NewChatFilter filter = NewChatFilter.contacts;

  @override
  void initState() {
    super.initState();
    directorySearch = UserDirectorySearch(
      client: Matrix.of(context).client,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    directorySearch.dispose();
    controller.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  /// The people the user already has a direct chat with, narrowed by what is
  /// typed. Local, so it answers every keystroke without a request.
  List<User> get contacts => Matrix.of(
    context,
  ).client.directChatContacts.matching(controller.text).sortedByDisplayname();

  void searchUsers([String? input]) {
    final searchTerm = input ?? controller.text;
    // Only the public filter spends a request; the contacts list re-filters
    // locally off the rebuild this setState triggers.
    if (filter == NewChatFilter.public) {
      directorySearch.search(searchTerm);
    }
    setState(() {});
  }

  void setFilter(NewChatFilter newFilter) {
    if (filter == newFilter) return;
    setState(() => filter = newFilter);
    // Switching to public with a term already typed searches it straight
    // away — the user has waited through the debounce once already.
    if (newFilter == NewChatFilter.public && controller.text.isNotEmpty) {
      directorySearch.searchNow(controller.text);
    }
  }

  void retrySearch() => directorySearch.searchNow(controller.text);

  void inviteAction() => FluffyShare.shareInviteLink(context);

  void copyUserId() async {
    await Clipboard.setData(
      ClipboardData(text: Matrix.of(context).client.userID!),
    );
    // #Pangea
    ScaffoldMessenger.of(context).showSnackBarAnnounced(
      SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
    );
    // Pangea#
  }

  void openUserModal(Profile profile) => UserDialog.show(
    context: context,
    profile: profile,
    uri: GoRouterState.of(context).uri,
  );

  @override
  Widget build(BuildContext context) =>
      NewPrivateChatView(this, closeButton: widget.closeButton);
}
