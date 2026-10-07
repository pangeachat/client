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

  /// Marks a stored copy whose id the module refused with a 409. Such a copy
  /// is listed, and sent, only under its [successorReportId] — never under
  /// the refused id again.
  static const _rejectedField = 'rejected_by_module';

  /// [userId]'s stored reports. A stored value that cannot be read is
  /// reported — by its key, never its contents, which hold the reason — and
  /// skipped; it is left in place rather than deleted.
  List<ReportSubmission> pending(String userId) => [
    for (final (_, report) in _entries(userId)) report,
  ];

  /// Each stored copy with the key it is stored under, already moved to its
  /// successor id when it is marked rejected.
  List<(String, ReportSubmission)> _entries(String userId) {
    final prefix = _userPrefix(userId);
    final entries = <(String, ReportSubmission)>[];
    for (final key in _prefs.getKeys().where((k) => k.startsWith(prefix))) {
      try {
        final json = jsonDecode(_prefs.getString(key)!) as Map<String, dynamic>;
        final report = ReportSubmission.fromJson(json);
        entries.add((
          key,
          json[_rejectedField] == true
              ? report.withReportId(successorReportId(report.reportId))
              : report,
        ));
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
    return entries;
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

  /// Rewrites the stored copy under [reportId] in place as refused, so it is
  /// only ever sent again under its successor id. Needs no more room than
  /// the copy already takes, so it can succeed where storing a second copy
  /// under the new id cannot.
  Future<void> markRejected(String userId, String reportId) async {
    final key = _key(userId, reportId);
    final raw = _prefs.getString(key);
    if (raw == null) throw StateError('no stored copy to mark');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    json[_rejectedField] = true;
    final ok = await _prefs.setString(key, jsonEncode(json));
    if (!ok) throw StateError('the pending report write was refused');
  }

  /// Drops the stored copy of [reportId], whether it is stored under that id
  /// or is a refused copy listed under it as its successor.
  Future<void> forget(String userId, String reportId) async {
    for (final (key, report) in _entries(userId)) {
      if (report.reportId != reportId) continue;
      final ok = await _prefs.remove(key);
      if (!ok) throw StateError('the pending report removal was refused');
    }
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

  // Each entry: the report, and whether it was already moved this run.
  final queue = [
    for (final report in await store.pendingFromDisk(userId)) (report, false),
  ];
  while (queue.isNotEmpty) {
    final (report, rotated) = queue.removeAt(0);
    final result = await attempt(report);
    if (result == CaptureResult.failed) continue;
    if (result == CaptureResult.conflict) {
      final fresh = report.withReportId(newReportId(report.reportId));
      final stored = await guarded(
        () => store.remember(userId, fresh),
        'remember',
      );
      if (stored) {
        await guarded(() => store.forget(userId, report.reportId), 'forget');
      } else {
        // No room for a second copy: mark the one there is, in place, so it
        // is listed under the new id from now on and never sent as the old.
        await guarded(
          () => store.markRejected(userId, report.reportId),
          'markRejected',
        );
      }
      // Sent under the new id now either way. A report already moved once
      // this run is sent again only on the next start, so a run cannot loop.
      if (!rotated) queue.add((fresh, true));
      continue;
    }
    // Recorded. A failed forget means a resend next start, which is harmless:
    // the module stores a report id once.
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
