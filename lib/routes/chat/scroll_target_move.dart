import 'package:matrix/matrix.dart';

/// What the chat must do to show a loaded event that its current view filters
/// out.
enum ScrollTargetMove {
  /// The event belongs in this view and is hidden by design (a kind the chat
  /// never shows): no view change can show it.
  none,

  /// The event is a reply in a thread that is not open: open that thread.
  enterThread,

  /// The event is in the main timeline while a thread is open: close it.
  closeThread,
}

ScrollTargetMove scrollTargetMove(Event event, String? activeThreadId) {
  final threadRoot = event.threadRootId;
  if (threadRoot == activeThreadId ||
      (activeThreadId != null && event.eventId == activeThreadId)) {
    return ScrollTargetMove.none;
  }
  return threadRoot != null
      ? ScrollTargetMove.enterThread
      : ScrollTargetMove.closeThread;
}

extension ThreadRootId on Event {
  /// The root of the thread this event replies in, or null in the main timeline.
  String? get threadRootId =>
      relationshipType == RelationshipTypes.thread ? relationshipEventId : null;
}
