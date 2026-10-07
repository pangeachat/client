import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/utils/report_api_extension.dart';

/// Reports the module has not yet confirmed, kept on the device so a report
/// survives the app being killed mid-send.
///
/// A report is written here before its first attempt and removed only when
/// the module confirms it (or refuses it in a way no retry can change), so
/// whatever is left is replayed on the next start with its original
/// `report_id` — which the module stores once, however many times it
/// arrives.
///
/// Keyed by the reporter's user id: a report can only be sent with the
/// reporter's own token.
class PendingReportStore {
  static const prefsKey = 'pangea.pending_reports';

  final SharedPreferences _prefs;

  PendingReportStore(this._prefs);

  static Future<PendingReportStore> open() async =>
      PendingReportStore(await SharedPreferences.getInstance());

  Map<String, List<ReportSubmission>> _readAll() {
    final raw = _prefs.getString(prefsKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (userId, reports) => MapEntry(
        userId,
        (reports as List)
            .map((r) => ReportSubmission.fromJson(r as Map<String, dynamic>))
            .toList(),
      ),
    );
  }

  Future<void> _writeAll(Map<String, List<ReportSubmission>> all) async {
    all.removeWhere((_, reports) => reports.isEmpty);
    final ok = await _prefs.setString(
      prefsKey,
      jsonEncode(
        all.map(
          (userId, reports) =>
              MapEntry(userId, reports.map((r) => r.toJson()).toList()),
        ),
      ),
    );
    if (!ok) throw StateError('pending report store write was refused');
  }

  List<ReportSubmission> pending(String userId) => _readAll()[userId] ?? [];

  /// Adds [report], or replaces the copy with the same report id.
  Future<void> remember(String userId, ReportSubmission report) async {
    final all = _readAll();
    all[userId] = [
      ...?all[userId]?.where((r) => r.reportId != report.reportId),
      report,
    ];
    await _writeAll(all);
  }

  Future<void> forget(String userId, String reportId) async {
    final all = _readAll();
    final reports = all[userId];
    if (reports == null) return;
    all[userId] = reports.where((r) => r.reportId != reportId).toList();
    await _writeAll(all);
  }
}

/// Sends every report [userId] left unconfirmed, each with its original
/// report id, and forgets the ones the module has settled. One that fails
/// again stays for the next start; its failure is already in Sentry.
Future<void> replayPendingReports({
  required PendingReportStore store,
  required String userId,
  required Future<CaptureResult> Function(ReportSubmission report) attempt,
}) async {
  for (final report in store.pending(userId)) {
    final result = await attempt(report);
    if (result != CaptureResult.failed) {
      await store.forget(userId, report.reportId);
    }
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
