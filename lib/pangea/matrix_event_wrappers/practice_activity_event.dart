import 'dart:developer';

import 'package:fluffychat/pangea/extensions/pangea_event_extension.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/practice_activity_record_event.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/practice_activity_model.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../constants/pangea_event_types.dart';

class PracticeActivityEvent {
  Event event;
  Timeline? timeline;
  PracticeActivityModel? _content;

  PracticeActivityEvent({
    required this.event,
    required this.timeline,
    content,
  }) {
    if (content != null) {
      if (!kDebugMode) {
        throw Exception(
          "content should not be set on product, just a dev placeholder",
        );
      } else {
        _content = content;
      }
    }
    if (event.type != PangeaEventTypes.pangeaActivity) {
      throw Exception(
        "${event.type} should not be used to make a PracticeActivityEvent",
      );
    }
  }

  PracticeActivityModel get practiceActivity {
    try {
      _content ??= event.getPangeaContent<PracticeActivityModel>();
      return _content!;
    } catch (e, s) {
      final contentMap = event.content;
      debugger(when: kDebugMode);
      rethrow;
    }
  }

  /// All completion records assosiated with this activity
  List<PracticeActivityRecordEvent> get allRecords {
    if (timeline == null) {
      debugger(when: kDebugMode);
      return [];
    }
    final List<Event> records = event
        .aggregatedEvents(timeline!, PangeaEventTypes.activityRecord)
        .toList();

    return records
        .map((event) => PracticeActivityRecordEvent(event: event))
        .toList();
  }

  /// Completion record assosiated with this activity
  /// for the logged in user, null if there is none
  PracticeActivityRecordEvent? get userRecord {
    final List<PracticeActivityRecordEvent> records = allRecords
        .where(
          (recordEvent) =>
              recordEvent.event.senderId ==
              recordEvent.event.room.client.userID,
        )
        .toList();
    if (records.length > 1) {
      debugPrint("There should only be one record per user per activity");
      debugger(when: kDebugMode);
    }
    return records.firstOrNull;
  }

  String get parentMessageId => event.relationshipEventId!;

  /// Checks if there are any user records in the list for this activity,
  /// and, if so, then the activity is complete
  bool get isComplete => userRecord != null;
}
