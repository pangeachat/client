import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/chat/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';

extension SupportClientExtension on Client {
  bool get hasSupportDM => rooms.any((r) => r.isSupportDM);

  Future<String> startChatWithSupport() =>
      createPangeaDirectChat(Environment.supportUserId);
}

extension SupportRoomExtension on Room {
  bool get isSupportDM =>
      isDirectChat && directChatMatrixID == Environment.supportUserId;
}
