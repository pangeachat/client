import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension BotEventExtension on Event {
  bool get isFirstBotDMMessage =>
      content[PangeaEventTypes.firstBotDMMessage] == true;
}
