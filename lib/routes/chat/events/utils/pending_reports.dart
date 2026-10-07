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

  /// How many times the module refused this copy's id with a 409. A copy
  /// refused n times is listed, sent and forgotten only under the n-th
  /// [successorReportId] of the id it was first stored under — never under a
  /// refused id again. Counted in place, so moving a report to a new id is a
  /// single write to its one key, with no second copy and nothing to delete.
  static const _generationsField = 'successor_generations';

  /// [userId]'s stored reports. A stored value that cannot be read is
  /// reported — by its key, never its contents, which hold the reason — and
  /// skipped; it is left in place rather than deleted.
  List<ReportSubmission> pending(String userId) => [
    for (final (_, report, _) in _entries(userId)) report,
  ];

  /// Each stored copy: its key, the report under the id it is sent as now,
  /// and its stored JSON.
  List<(String, ReportSubmission, Map<String, dynamic>)> _entries(
    String userId,
  ) {
    final prefix = _userPrefix(userId);
    final entries = <(String, ReportSubmission, Map<String, dynamic>)>[];
    for (final key in _prefs.getKeys().where((k) => k.startsWith(prefix))) {
      try {
        final json = jsonDecode(_prefs.getString(key)!) as Map<String, dynamic>;
        var report = ReportSubmission.fromJson(json);
        final generations = json[_generationsField] as int? ?? 0;
        for (var i = 0; i < generations; i++) {
          report = report.withReportId(successorReportId(report.reportId));
        }
        entries.add((key, report, json));
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

  /// Runs one write. A write that fails can leave the preference cache
  /// holding a value the platform store never took, so the cache is re-read
  /// from the platform store before the failure is raised: every later read
  /// — and so every later decision to write or skip — sees what is really
  /// stored.
  Future<void> _write(Future<bool> Function() write) async {
    bool ok;
    try {
      ok = await write();
    } catch (_) {
      await _prefs.reload();
      rethrow;
    }
    if (!ok) {
      await _prefs.reload();
      throw StateError('the pending report write was refused');
    }
  }

  /// Stores [report] unless it is already stored: under its own key — a
  /// report id always names the same report, and rewriting that key could
  /// undo a move [markRejected] made to it — or as a copy [markRejected]
  /// moved to this id. The cache is trustworthy here because [_write]
  /// re-reads the platform store after any refused write.
  Future<void> remember(String userId, ReportSubmission report) async {
    final key = _key(userId, report.reportId);
    if (_prefs.containsKey(key) ||
        _entries(userId).any((e) => e.$2.reportId == report.reportId)) {
      return;
    }
    await _write(() => _prefs.setString(key, jsonEncode(report.toJson())));
  }

  /// Moves the copy listed under [reportId], which the module refused with a
  /// 409, to its [successorReportId], in place: one write to its own key,
  /// needing no more room than it already takes.
  Future<void> markRejected(String userId, String reportId) async {
    final entry = _entries(userId).where((e) => e.$2.reportId == reportId);
    if (entry.isEmpty) throw StateError('no stored copy to mark');
    final (key, _, json) = entry.first;
    json[_generationsField] = (json[_generationsField] as int? ?? 0) + 1;
    await _write(() => _prefs.setString(key, jsonEncode(json)));
  }

  /// Drops every copy listed under [reportId].
  Future<void> forget(String userId, String reportId) async {
    for (final (key, report, _) in _entries(userId)) {
      if (report.reportId != reportId) continue;
      await _write(() => _prefs.remove(key));
    }
  }
}

/// Sends every report [userId] left unconfirmed, each with its original
/// report id, and forgets the ones the module confirms. One that fails again
/// stays for the next start; its failure is already in Sentry.
///
/// A [CaptureResult.conflict] means the id is already the module's for
/// another report: the stored copy is moved, in place, to the id's
/// [successorReportId] and sent once more under it now. A store failure is
/// reported and never stops the others.
Future<void> replayPendingReports({
  required PendingReportStore store,
  required String userId,
  required Future<CaptureResult> Function(ReportSubmission report) attempt,
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
    final fresh = report.withReportId(successorReportId(report.reportId));
    if (result == CaptureResult.conflict) {
      final moved = await guarded(
        () => store.markRejected(userId, report.reportId),
        'markRejected',
      );
      if (!moved) {
        // The new id is stored on its own, and the copy under the refused id
        // is dropped regardless: a refused id must never be replayed.
        await guarded(() => store.remember(userId, fresh), 'remember');
        await guarded(() => store.forget(userId, report.reportId), 'forget');
      }
      // Sent under the new id now. A report already moved once this run is
      // sent again only on the next start, so a run cannot loop.
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
