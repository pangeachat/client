import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/routes/chat_list/room_invite_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

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

  /// Whether an invite to [space] is one the client accepts without asking the
  /// user — a child of a course they're already in, or the approval of a knock
  /// they sent themselves. Everything else needs an explicit accept/decline.
  static bool isAutoAcceptedInvite(Room space) {
    if (space.hasKnocked) return true;

    final joinedSpaces = space.client.rooms.where(
      (element) => element.isSpace && element.membership == Membership.join,
    );

    return joinedSpaces.any(
      (s) => s.spaceChildren.any((c) => c.roomId == space.id),
    );
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

    if (isAutoAcceptedInvite(space)) {
      return autoJoin(context, space);
    }

    await RoomInviteDialog.show(context, space);
    return null;
  }
}
