import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';

/// One [PangeaMessageEvent] per event id, reused across timeline rebuilds so
/// its parsed-representation memo survives them (#8393 stage 2). Previously
/// every rebuild of every visible message re-parsed all representation and
/// token JSON from scratch.
///
/// Correctness relies on two invalidation paths:
/// - Local mutations (edits, translation requests, token corrections, STT)
///   already clear the wrapper's memo internally — reusing the instance
///   keeps that working.
/// - Representations and edits arriving via sync only show up in
///   [Timeline.aggregatedEvents], which the old rebuild-time reconstruction
///   picked up implicitly. [get] re-derives a cheap stamp from those
///   aggregations on every hit and refreshes the memo when it changes.
///
/// The cache is bound to one [Timeline] instance: a controller can replace
/// its timeline (e.g. jump-to-event), and a wrapper holds the timeline it
/// was built with, so on a different instance everything is discarded.
class PangeaMessageEventCache {
  final Map<String, PangeaMessageEvent> _entries = {};
  final Map<String, int> _stamps = {};
  Timeline? _timeline;

  PangeaMessageEvent get(
    Event event,
    Timeline timeline, {
    required bool ownMessage,
  }) {
    if (!identical(_timeline, timeline)) {
      clear();
      _timeline = timeline;
    }

    final stamp = _aggregationStamp(event, timeline);
    final cached = _entries[event.eventId];
    if (cached != null) {
      if (_stamps[event.eventId] != stamp) {
        cached.updateLatestEdit();
        _stamps[event.eventId] = stamp;
      }
      return cached;
    }

    final fresh = PangeaMessageEvent(
      event: event,
      timeline: timeline,
      ownMessage: ownMessage,
    );
    _entries[event.eventId] = fresh;
    _stamps[event.eventId] = stamp;
    return fresh;
  }

  static int _aggregationStamp(Event event, Timeline timeline) {
    final aggregations = timeline.aggregatedEvents[event.eventId];
    if (aggregations == null) return 0;
    final representations =
        aggregations[PangeaEventTypes.representation]?.length ?? 0;
    final edits = aggregations[RelationshipTypes.edit]?.length ?? 0;
    return (representations << 16) ^ edits;
  }

  void clear() {
    _entries.clear();
    _stamps.clear();
    _timeline = null;
  }
}
