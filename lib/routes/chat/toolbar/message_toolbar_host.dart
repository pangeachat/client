import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_request.dart';

/// The environment hosting the message toolbar overlay.
///
/// The toolbar historically lived only in chat, driven by [ChatController].
/// Hosts outside chat (e.g. the analytics vocab details page's example
/// messages, #8081) implement this narrow surface instead. Chat-only
/// functionality is reached through [chatController], which is null for
/// non-chat hosts — widgets in the toolbar subtree must gate those features
/// on its presence.
abstract class MessageToolbarHost {
  Room get room;

  /// Nullable to match [ChatController.timeline]; non-null by the time the
  /// toolbar is open (chat asserts this before showing it).
  Timeline? get timeline;

  void setSelectedEvent(Event event);

  void clearSelectedEvents();

  Future<void> showTokenFeedbackDialog(
    TokenInfoFeedbackRequestData requestData,
    String langCode,
    PangeaMessageEvent event,
  );

  /// The chat-only surface (practice, more menu, tutorials, regenerate,
  /// reply-scroll, button messages). Null when the toolbar is hosted
  /// outside chat.
  ChatController? get chatController;
}

/// Which optional toolbar features the host displays.
class MessageToolbarConfig {
  final bool showPracticeButton;
  final bool showMoreButton;
  final bool showReactionPicker;

  /// Word-card lemma taps navigate to the construct's analytics page. Off for
  /// hosts already on an analytics page, where navigating would change the
  /// page underneath the open overlay.
  final bool enableWordCardAnalyticsNavigation;

  const MessageToolbarConfig({
    required this.showPracticeButton,
    required this.showMoreButton,
    required this.showReactionPicker,
    required this.enableWordCardAnalyticsNavigation,
  });

  static const chat = MessageToolbarConfig(
    showPracticeButton: true,
    showMoreButton: true,
    showReactionPicker: true,
    enableWordCardAnalyticsNavigation: true,
  );

  static const analyticsExample = MessageToolbarConfig(
    showPracticeButton: false,
    showMoreButton: false,
    showReactionPicker: false,
    enableWordCardAnalyticsNavigation: false,
  );
}
