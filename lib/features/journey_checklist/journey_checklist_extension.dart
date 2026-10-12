import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/journey_checklist/journey_checklist_model.dart';
import 'package:fluffychat/features/journey_checklist/journey_checklist_writes.dart';
import 'package:fluffychat/features/journey_checklist/journey_step_enum.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension JourneyChecklistExtension on Client {
  /// The synced checklist, plus anything this client wrote that has not
  /// synced back yet — a write replaces the whole event, so building on the
  /// synced copy alone would drop a step recorded moments earlier.
  JourneyChecklistModel get journeyChecklist {
    final content = accountData[PangeaEventTypes.journeyChecklist]?.content;
    final synced = content == null
        ? const JourneyChecklistModel()
        : JourneyChecklistModel.fromJson(content);
    final unsynced = JourneyChecklistWrites.lastWritten[userID];
    return unsynced == null ? synced : synced.merge(unsynced);
  }

  /// Saves when [step] first happened; a later occurrence writes nothing.
  /// Called only through `JourneyMoments`, which sends each step's GA mirror
  /// with it. Never throws: a failed save is reported and the step is retried
  /// on its next occurrence.
  Future<void> recordJourneyStep(JourneyStep step, {DateTime? at}) {
    final userId = userID;
    if (userId == null) {
      return ErrorHandler.logError(
        e: 'Journey step recorded with no signed-in user',
        data: {'step': step.key},
        level: SentryLevel.warning,
      );
    }
    return JourneyChecklistWrites.serialize(
      userId,
      () => _writeStep(userId, step, at ?? DateTime.now()),
    );
  }

  Future<void> _writeStep(String userId, JourneyStep step, DateTime at) async {
    final current = journeyChecklist;
    if (current.hasStep(step)) return;
    if (current.hadMalformedField) {
      ErrorHandler.logErrorOnce(
        key: 'journey_checklist_malformed',
        e: 'Journey checklist held a field this client could not read',
        data: {'step': step.key},
        level: SentryLevel.warning,
      );
    }
    final previous = JourneyChecklistWrites.lastWritten[userId];
    final updated = current.withStep(step, at);
    JourneyChecklistWrites.lastWritten[userId] = updated;
    try {
      await setAccountData(
        userId,
        PangeaEventTypes.journeyChecklist,
        updated.toJson(),
      );
    } catch (e, s) {
      JourneyChecklistWrites.restore(userId, previous);
      ErrorHandler.logError(e: e, s: s, data: {'step': step.key});
    }
  }
}
