import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/user_search_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';

// #Pangea
// Pangea#

class NewPrivateChat extends StatefulWidget {
  final Widget? closeButton;

  const NewPrivateChat({super.key, this.closeButton});

  @override
  NewPrivateChatController createState() => NewPrivateChatController();
}

class NewPrivateChatController extends State<NewPrivateChat> {
  final TextEditingController controller = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();

  Future<List<Profile>>? searchResponse;

  Timer? _searchCoolDown;

  static const Duration _coolDown = Duration(milliseconds: 500);

  void searchUsers([String? input]) async {
    final searchTerm = input ?? controller.text;
    if (searchTerm.isEmpty) {
      _searchCoolDown?.cancel();
      setState(() {
        searchResponse = _searchCoolDown = null;
      });
      return;
    }

    _searchCoolDown?.cancel();
    _searchCoolDown = Timer(_coolDown, () {
      setState(() {
        searchResponse = _searchUser(searchTerm);
      });
    });
  }

  Future<List<Profile>> _searchUser(String searchTerm) async {
    // #Pangea
    // final result = await Matrix.of(
    //   context,
    // ).client.searchUserDirectory(searchTerm);
    final result = await Matrix.of(context).client.searchUser(searchTerm);
    // Pangea#
    final profiles = result.results;

    // #Pangea
    // if (searchTerm.isValidMatrixId &&
    //     searchTerm.sigil == '@' &&
    //     !profiles.any((profile) => profile.userId == searchTerm)) {
    //   profiles.add(Profile(userId: searchTerm));
    // }
    // Pangea#

    return profiles;
  }

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
