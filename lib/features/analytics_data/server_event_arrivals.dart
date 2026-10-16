import 'dart:async';

import 'package:matrix/matrix.dart';

/// Collects the ids of the events the server syncs into [room], from creation
/// until [cancel]. Create it before sending: the sync that carries an event
/// can arrive before its send returns.
class ServerEventArrivals {
  ServerEventArrivals(this.room) {
    _subscription = room.client.onSync.stream.listen(_onSync);
  }

  final Room room;
  final Set<String> _arrivedIds = {};
  late final StreamSubscription<SyncUpdate> _subscription;
  String? _awaitedId;
  Completer<void>? _awaitedArrival;

  void _onSync(SyncUpdate update) {
    final events = update.rooms?.join?[room.id]?.timeline?.events ?? [];
    _arrivedIds.addAll(events.map((event) => event.eventId));
    if (_arrivedIds.contains(_awaitedId)) {
      _awaitedArrival?.complete();
      _awaitedArrival = null;
    }
  }

  /// Whether [eventId] arrived from the server within [timeout].
  Future<bool> waitFor(String eventId, Duration timeout) async {
    if (_arrivedIds.contains(eventId)) return true;
    _awaitedId = eventId;
    final arrival = _awaitedArrival = Completer<void>();
    try {
      await arrival.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> cancel() => _subscription.cancel();
}
