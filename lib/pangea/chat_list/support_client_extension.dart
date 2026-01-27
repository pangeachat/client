import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';

extension SupportClientExtension on Client {
  bool get hasSupportDM => rooms.any((r) => r.isSupportDM);
}

extension SupportRoomExtension on Room {
  bool get isSupportDM =>
      isDirectChat && directChatMatrixID == Environment.supportUserId;
}
