import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/routes/chat/toolbar/message_toolbar_host.dart';

/// A toolbar host with no chat and no timeline, for rendering a message's
/// content outside a chat.
class FakeMessageToolbarHost implements MessageToolbarHost {
  FakeMessageToolbarHost(this.room);

  @override
  final Room room;

  @override
  Timeline? get timeline => null;

  @override
  ChatController? get chatController => null;

  @override
  void setSelectedEvent(Event event) {}

  @override
  void clearSelectedEvents() {}

  @override
  Future<void> showTokenFeedbackDialog(
    TokenInfoFeedbackRequestData requestData,
    String langCode,
    PangeaMessageEvent event,
  ) async {}
}
