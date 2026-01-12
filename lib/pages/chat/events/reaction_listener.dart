import 'dart:async';

import 'package:matrix/matrix.dart';

class ReactionListener {
  final Event event;
  final Function(SyncUpdate) onUpdate;

  StreamSubscription? _reactionSub;

  ReactionListener({required this.event, required this.onUpdate}) {
    _reactionSub = event.room.client.onSync.stream.where(
      (update) {
        final room = event.room;
        final timelineEvents = update.rooms?.join?[room.id]?.timeline?.events;
        if (timelineEvents == null) return false;

        final eventID = event.eventId;
        return timelineEvents.any(
          (e) =>
              e.type == EventTypes.Redaction ||
              (e.type == EventTypes.Reaction &&
                  Event.fromMatrixEvent(e, room).relationshipEventId ==
                      eventID),
        );
      },
    ).listen(onUpdate);
  }

  void dispose() {
    _reactionSub?.cancel();
    _reactionSub = null;
  }
}
