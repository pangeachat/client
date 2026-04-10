import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/pangea/user/user_invite_controller.dart';

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
      await UserInviteController.setInviteUser(widget.userID);
      context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox();
}
