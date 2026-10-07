import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/utils/report_api_extension.dart';

/// Reports the module has not yet confirmed, kept on the device so a report
/// survives the app being killed mid-send.
///
/// A report is written here before each attempt and removed only when the
/// module confirms it, so whatever is left is replayed on the next start
/// with its original `report_id` — which the module stores once, however
/// many times it arrives.
///
/// One preference per report, keyed by the reporter's user id (a report can
/// only be sent with the reporter's own token) and the report id. Each write
/// touches only its own key, so two copies of the app — two web tabs — each
/// holding a stale preference cache cannot erase each other's reports.
class PendingReportStore {
  static const keyPrefix = 'pangea.pending_report';

  final SharedPreferences _prefs;

  PendingReportStore(this._prefs);

  static Future<PendingReportStore> open() async =>
      PendingReportStore(await SharedPreferences.getInstance());

  static String _userPrefix(String userId) => '$keyPrefix|$userId|';

  static String _key(String userId, String reportId) =>
      '${_userPrefix(userId)}$reportId';

  /// [userId]'s stored reports. A stored value that cannot be read is
  /// reported — by its key, never its contents, which hold the reason — and
  /// skipped; it is left in place rather than deleted.
  List<ReportSubmission> pending(String userId) {
    final prefix = _userPrefix(userId);
    final reports = <ReportSubmission>[];
    for (final key in _prefs.getKeys().where((k) => k.startsWith(prefix))) {
      try {
        reports.add(
          ReportSubmission.fromJson(
            jsonDecode(_prefs.getString(key)!) as Map<String, dynamic>,
          ),
        );
      } catch (e) {
        // Not the caught error: a FormatException quotes the stored text.
        unawaited(
          ErrorHandler.logError(
            e: 'A stored pending report is unreadable (${e.runtimeType})',
            data: {'key': key.substring(keyPrefix.length)},
          ),
        );
      }
    }
    return reports;
  }

  /// [pending], after re-reading the platform store: another copy of the
  /// app (another web tab) may have stored reports since this one loaded its
  /// preference cache.
  Future<List<ReportSubmission>> pendingFromDisk(String userId) async {
    await _prefs.reload();
    return pending(userId);
  }

  /// Stores [report], replacing any copy with the same report id.
  Future<void> remember(String userId, ReportSubmission report) async {
    final ok = await _prefs.setString(
      _key(userId, report.reportId),
      jsonEncode(report.toJson()),
    );
    if (!ok) throw StateError('the pending report write was refused');
  }

  Future<void> forget(String userId, String reportId) async {
    final ok = await _prefs.remove(_key(userId, reportId));
    if (!ok) throw StateError('the pending report removal was refused');
  }
}

/// Sends every report [userId] left unconfirmed, each with its original
/// report id, and forgets the ones the module confirms. One that fails again
/// stays for the next start; its failure is already in Sentry.
///
/// A [CaptureResult.conflict] means the id is already the module's for
/// another report, so the report is moved to the id [newReportId] derives —
/// the new copy stored before the old one is dropped — and sent once more
/// under it now. A store failure is reported and never stops the others.
Future<void> replayPendingReports({
  required PendingReportStore store,
  required String userId,
  required Future<CaptureResult> Function(ReportSubmission report) attempt,
  required String Function(String rejectedId) newReportId,
}) async {
  Future<bool> guarded(Future<void> Function() write, String what) async {
    try {
      await write();
      return true;
    } catch (e, s) {
      await ErrorHandler.logError(
        e: e,
        s: s,
        data: {'where': 'PendingReportStore.$what'},
      );
      return false;
    }
  }

  final queue = [
    for (final report in await store.pendingFromDisk(userId)) (report, false),
  ];
  while (queue.isNotEmpty) {
    final (report, rotated) = queue.removeAt(0);
    final result = await attempt(report);
    if (result == CaptureResult.failed) continue;
    if (result == CaptureResult.conflict) {
      // A report already moved once this run waits for the next start
      // rather than rotating again.
      if (rotated) continue;
      final fresh = report.withReportId(newReportId(report.reportId));
      if (!await guarded(() => store.remember(userId, fresh), 'remember')) {
        continue;
      }
      queue.add((fresh, true));
    }
    // Replayed again next start if this fails, which is harmless: the module
    // stores a report id once.
    await guarded(() => store.forget(userId, report.reportId), 'forget');
  }
}

/// Replays an account's unconfirmed reports once it is logged in. Started per
/// account alongside the other account services in `MatrixState`.
class PendingReportReplay {
  final Client client;
  bool _disposed = false;

  PendingReportReplay({required this.client});

  Future<void> start() async {
    try {
      if (!client.isLogged()) {
        await client.onLoginStateChanged.stream.firstWhere(
          (state) => state == LoginState.loggedIn,
        );
      }
      final userId = client.userID;
      if (_disposed || userId == null) return;
      await replayPendingReports(
        store: await PendingReportStore.open(),
        userId: userId,
        attempt: (report) async => _disposed
            ? CaptureResult.failed
            : attemptReportCapture(client, report),
        newReportId: successorReportId,
      );
    } catch (e, s) {
      // The reports stay stored and are tried again on the next start.
      await ErrorHandler.logError(
        e: e,
        s: s,
        data: {'where': 'PendingReportReplay.start'},
      );
    }
  }

  void dispose() => _disposed = true;
}
