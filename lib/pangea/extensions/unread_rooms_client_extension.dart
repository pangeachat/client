import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';

extension UnreadRoomsClientExtension on Client {
  /// The rooms an unread badge can count: unread or invited, and neither a
  /// space nor hidden. Read once per sync-driven rebuild and narrowed per
  /// badge, rather than scanned by every badge (#9236).
  List<Room> get unreadRooms => rooms
      .where((r) => r.isUnreadOrInvited && !r.isSpace && !r.isHiddenRoom)
      .toList();
}
