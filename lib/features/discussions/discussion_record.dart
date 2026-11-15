import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Keeps the learner's saved list in step with their discussion seats
/// (activities.instructions.md, "Discussions"). The server saves a
/// discussion: "I'm done" stamps the learner's own seat finished and archived
/// together (synapse `discussion_room`), and "Wait, I'm not done" clears both.
/// What is left to the client is the record the roleplay save also writes,
/// the session filed in the analytics room for its language, and the
/// completion it reports; a reopened seat comes off that list again, so the
/// list, the XP and the Learning Objectives page all agree with the seat.
class DiscussionRecord {
  /// Writes a session onto, or [unfile] takes it off, the learner's saved
  /// list for its language; false when there is no analytics room for that
  /// language. A failed write throws.
  final Future<bool> Function(String roomId, LanguageModel lang) file;
  final Future<bool> Function(String roomId, LanguageModel lang) unfile;

  /// Reports the completion of a discussion this run filed.
  final void Function(Room room, ActivityPlanModel plan, DateTime archivedAt)
  onCompleted;

  /// Whether the session is on the saved list for [lang] as this client last
  /// synced it.
  final bool Function(Room room, LanguageModel lang) _isFiled;

  DiscussionRecord({
    required this.file,
    required this.unfile,
    required this.onCompleted,
    bool Function(Room room, LanguageModel lang)? isFiled,
  }) : _isFiled = isFiled ?? _filedInAnalyticsRoom;

  /// The archived-at of each seat this run found filed or filed itself, so a
  /// pass before the analytics room's echo lands files nothing twice. Cleared
  /// when the seat reopens.
  final Map<String, DateTime> _filed = {};

  /// Rooms with a write on its way; a second pass waits for the next one.
  final Set<String> _writing = {};

  static bool _filedInAnalyticsRoom(Room room, LanguageModel lang) =>
      room.client
          .ownAnalyticsRoomLocal(lang: lang)
          ?.activityRoomIds
          .contains(room.id) ??
      false;

  /// Files [room] when the learner's seat is ended, and unfiles it when the
  /// seat was reopened.
  Future<void> sync(Room room) async {
    final seat = room.ownRoleState;
    // No seat: an admin reading along, with nothing to file.
    if (seat == null) return;
    final plan = room.activityPlan;
    // silent-ok: a plan still loading; the caller retries when the repo notifies
    if (plan == null) return;
    final lang = PLanguageStore.byLangCode(
      plan.req.targetLanguage.split("-").first,
    );
    if (lang == null) {
      ErrorHandler.logErrorOnce(
        key: 'discussion_record_language:${plan.req.targetLanguage}',
        e: StateError('A discussion\'s language is not in the language store'),
        data: {'roomId': room.id, 'targetLanguage': plan.req.targetLanguage},
      );
      return;
    }
    final archivedAt = seat.archivedAt;
    if (seat.isFinished && archivedAt != null) {
      await _fileEnded(room, plan, lang, archivedAt);
    } else {
      await _unfileReopened(room, lang);
    }
  }

  /// A session already on the list was filed, and counted, by an earlier
  /// run or another device. Otherwise the successful write is what counts
  /// it, at once: its echo can reach this client after an unrelated sync of
  /// the analytics room ends the write's wait, and a check of the local list
  /// then would read it as unfiled and drop the completion for good.
  Future<void> _fileEnded(
    Room room,
    ActivityPlanModel plan,
    LanguageModel lang,
    DateTime archivedAt,
  ) async {
    if (_filed[room.id] == archivedAt) return;
    if (_isFiled(room, lang)) {
      _filed[room.id] = archivedAt;
      return;
    }
    await _write(room, lang, () async {
      if (!await file(room.id, lang)) {
        throw StateError('No analytics room to file an ended discussion in');
      }
      _filed[room.id] = archivedAt;
      onCompleted(room, plan, archivedAt);
    });
  }

  Future<void> _unfileReopened(Room room, LanguageModel lang) async {
    _filed.remove(room.id);
    if (!_isFiled(room, lang)) return;
    await _write(room, lang, () async {
      if (!await unfile(room.id, lang)) {
        throw StateError('No analytics room to unfile a reopened discussion');
      }
    });
  }

  Future<void> _write(
    Room room,
    LanguageModel lang,
    Future<void> Function() write,
  ) async {
    if (!_writing.add(room.id)) return;
    try {
      await write();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': room.id, 'lang': lang.langCode},
      );
    } finally {
      _writing.remove(room.id);
    }
  }
}
