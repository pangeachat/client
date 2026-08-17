import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/dm_invite/dm_invite_controller.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The `/invite_user/:userID` landing (the "Share invite link" URL, #8436):
/// a transient full-screen page that opens the DM with the invited user and
/// navigates straight into it over the chat list — the link IS the DM, so the
/// user never has to find it by opening Chats first.
///
/// Only ever rendered logged in with an L2 set (the route wears the `/` auth
/// guard, which bounces or onboards otherwise). It is also the consumer of the
/// login-bounce ferry's DM invite entry (SpaceCodeRepo.dmInviteUserId): the
/// cache clears only once the DM has actually opened, or the open has
/// definitively failed — never on mount, which proved lossy for the other
/// ferried links (a competing boot-time navigation can dispose a landing right
/// after it mounts). A disposed-mid-open landing leaves the cache in place, so
/// the next `/` landing re-enters here and joins the still-in-flight open
/// (DmInviteController) instead of losing the DM or creating a second one.
class DmInviteLandingPage extends StatefulWidget {
  final String userId;
  const DmInviteLandingPage({super.key, required this.userId});

  @override
  State<DmInviteLandingPage> createState() => _DmInviteLandingPageState();
}

class _DmInviteLandingPageState extends State<DmInviteLandingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openDm());
  }

  Future<void> _openDm() async {
    if (!mounted) return;
    final client = Matrix.of(context).client;
    final userId = widget.userId;

    // Own invite link (#6361): there is no DM with oneself to open; the
    // chat list is the honest landing, and the ferry is spent.
    if (userId == client.userID) {
      await SpaceCodeRepo.clearDmInviteUserId();
      if (mounted) context.go(PRoutes.chatsList);
      return;
    }

    final result = await showFutureLoadingDialog(
      context: context,
      future: () => DmInviteController.openDirectChat(client, userId),
    );
    final roomId = result.result;
    if (roomId == null) {
      // The open failed (the error is already on screen): spend the ferry so
      // a bad link cannot loop the `/` guard back here, and leave the user in
      // the app rather than on this blank page.
      await SpaceCodeRepo.clearDmInviteUserId();
      if (mounted) context.go(PRoutes.chatsList);
      return;
    }

    // Disposed mid-open (a competing navigation): keep the ferry so the next
    // `/` landing re-enters and lands the DM.
    if (!mounted) return;
    await SpaceCodeRepo.clearDmInviteUserId();
    if (!mounted) return;
    context.go(WorkspaceNav.openRoomById(Uri.parse(PRoutes.chatsList), roomId));
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
}
