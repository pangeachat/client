import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/journey_checklist/journey_checklist_model.dart';

/// Per-account write order and the last checklist written, so two steps
/// recorded before the first write syncs back both land.
abstract class JourneyChecklistWrites {
  static final Map<String, JourneyChecklistModel> lastWritten = {};
  static final Map<String, Future<void>> _queues = {};

  static Future<void> serialize(String userId, Future<void> Function() write) {
    final next = (_queues[userId] ?? Future.value()).then((_) => write());
    _queues[userId] = next;
    return next;
  }

  static void restore(String userId, JourneyChecklistModel? previous) {
    if (previous == null) {
      lastWritten.remove(userId);
    } else {
      lastWritten[userId] = previous;
    }
  }

  @visibleForTesting
  static void reset() {
    lastWritten.clear();
    _queues.clear();
  }
}
