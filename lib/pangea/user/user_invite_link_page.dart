import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/chat/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/user/user_invite_link_repo.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class UserInviteLink extends StatefulWidget {
  final String userID;
  const UserInviteLink({super.key, required this.userID});

  @override
  State<UserInviteLink> createState() => UserInviteLinkState();
}

class UserInviteLinkState extends State<UserInviteLink> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      bool isLogged = false;
      try {
        isLogged = Matrix.of(context).client.isLogged();
      } catch (e, s) {
        Logs().e('Error checking login status', e, s);
      }

      if (!isLogged) {
        await UserInviteLinkRepo.setInviteUser(widget.userID);
        context.go('/home');
        return;
      }

      final result = await _startDM();
      if (!mounted) return;

      if (result.result == null) {
        context.go('/home');
        return;
      }

      final roomId = result.result!;
      context.go('/rooms/$roomId');
    });
  }

  Future<Result<String>> _startDM() async {
    try {
      final client = Matrix.of(context).client;
      final roomId = await client
          .createPangeaDirectChat(widget.userID)
          .timeout(Duration(seconds: 10));
      return Result.value(roomId);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"userID": widget.userID});
      return Result.error(e);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox();
}
