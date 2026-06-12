import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';

extension SupportClientExtension on Client {
  bool get hasSupportDM => rooms.any((r) => r.isSupportDM);

  Future<String> startChatWithSupport() =>
      createPangeaDirectChat(Environment.supportUserId);
}

extension SupportRoomExtension on Room {
  bool get isSupportDM =>
      isDirectChat && directChatMatrixID == Environment.supportUserId;
}
