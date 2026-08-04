import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/utils/stream_extension.dart';

/// Loads and watches the users knocking on [room], rebuilding [builder] as
/// knocks arrive or get resolved (accepted → invite, denied → leave), so a
/// knock indicator clears exactly when the admin acts on it (#8139).
///
/// Only admins can accept/deny a knock, so for non-admins (and rooms the user
/// hasn't joined) this never requests the member list and always builds with
/// an empty list — knock indicators are admin-only by design.
class KnockingUsersBuilder extends StatefulWidget {
  final Room room;
  final Widget Function(BuildContext context, List<User> knockingUsers) builder;

  const KnockingUsersBuilder({
    super.key,
    required this.room,
    required this.builder,
  });

  @override
  State<KnockingUsersBuilder> createState() => KnockingUsersBuilderState();
}

class KnockingUsersBuilderState extends State<KnockingUsersBuilder> {
  List<User> _knockingUsers = [];
  StreamSubscription? _memberSubscription;

  @override
  void initState() {
    super.initState();
    _setKnockingSubscription();
  }

  @override
  void didUpdateWidget(covariant KnockingUsersBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _setKnockingSubscription();
    }
  }

  @override
  void dispose() {
    _memberSubscription?.cancel();
    super.dispose();
  }

  bool _isMemberUpdate(({String roomId, StrippedStateEvent state}) event) =>
      event.roomId == widget.room.id &&
      event.state.type == EventTypes.RoomMember;

  void _setKnockingSubscription() {
    _memberSubscription?.cancel();
    _knockingUsers = widget.room.knockingUsers;

    if (widget.room.membership != Membership.join || !widget.room.isRoomAdmin) {
      return;
    }

    _memberSubscription = widget.room.client.onRoomState.stream
        .where(_isMemberUpdate)
        .rateLimit(const Duration(seconds: 1))
        .listen((_) => _setKnockingUsers());

    widget.room
        .requestParticipants(
          [Membership.join, Membership.invite, Membership.knock],
          false,
          true,
        )
        .then((_) => _setKnockingUsers());
  }

  void _setKnockingUsers() {
    if (mounted) {
      setState(() {
        _knockingUsers = widget.room.knockingUsers;
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _knockingUsers);
}
