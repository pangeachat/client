import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/support/support_client_extension.dart';

extension WritingAssistanceRoomExtension on Room {
  bool get enableAutomaticWritingAssistance => !isSupportDM;
}
