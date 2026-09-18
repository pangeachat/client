import 'dart:async';

import 'package:matrix/matrix.dart';

class ReactionListener {
  final Event event;
  final void Function() onUpdate;

  StreamSubscription? _reactionSub;
  StreamSubscription? _cancelledSendSub;

  ReactionListener({required this.event, required this.onUpdate}) {
    final client = event.room.client;
    _reactionSub = client.onSync.stream
        .where((update) {
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
        })
        .listen((_) => onUpdate());

    // A discarded failed reaction leaves the timeline without a sync. The
    // timeline subscribed to this stream first, so it has already dropped it.
    _cancelledSendSub = client.onCancelSendEvent.stream.listen(
      (_) => onUpdate(),
    );
  }

  void dispose() {
    _reactionSub?.cancel();
    _reactionSub = null;
    _cancelledSendSub?.cancel();
    _cancelledSendSub = null;
  }
}
