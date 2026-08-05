import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';

extension CustomRoomDisplayExtension on Room {
  String senderDisplayName(User user, L10n l10n) {
    final displayName = user.localizedDisplayname(l10n);
    if (showActivityChatUI) {
      final role = activityRoles?.role(user.id);
      if (role?.role == null) return displayName;
      return "${role!.role} | $displayName";
    }

    return displayName;
  }
}
