import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/routes/chat_list/room_invite_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SpaceTapUtil {
  static Future<JoinResponse?> autoJoin(
    BuildContext context,
    Room space,
  ) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: space.joinKnockedRoom,
    );
    return resp.result;
  }

  static Future<JoinResponse?> onInviteTap(
    BuildContext context,
    Room space,
  ) async {
    final justInputtedCode = SpaceCodeRepo.recentCode;
    final spaceCode = space.joinCode;
    if (spaceCode != null && justInputtedCode == spaceCode) {
      return null;
    }

    final rooms = Matrix.of(context).client.rooms.where(
      (element) => element.isSpace && element.membership == Membership.join,
    );

    final isSpaceChild = rooms.any(
      (s) => s.spaceChildren.any((c) => c.roomId == space.id),
    );

    if (isSpaceChild || space.hasKnocked) {
      return autoJoin(context, space);
    }

    await RoomInviteDialog.show(context, space);
    return null;
  }
}
