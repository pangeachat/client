import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/utils/report_api_extension.dart';

/// The id of the revision of [event] the reporter is looking at.
///
/// An edited message renders its latest `m.replace` (only the author's own
/// edits count — the same rule [Event.getDisplayEvent] applies when drawing
/// it), so that replacement is what gets reported and snapshotted, never the
/// original text the reporter no longer sees.
String displayedRevisionId(Event event, Timeline timeline) =>
    event.getDisplayEvent(timeline).eventId;

/// A course space's joined members and their power levels, as far as this
/// client can see them.
class CourseRoster {
  final String courseId;

  /// Joined members only, keyed by user id.
  final Map<String, int> joinedPowerLevels;

  const CourseRoster({required this.courseId, required this.joinedPowerLevels});

  bool hasStudent(String userId, {required String botId}) {
    if (userId == botId) return false;
    final powerLevel = joinedPowerLevels[userId];
    return powerLevel != null && powerLevel < 100;
  }
}

/// The courses whose admins may be pointed to a report: the courses this
/// client can see in which the reported user is a student.
///
/// The module files a report under the reported user's student courses, or,
/// only when the reported user is a student nowhere, under the reporter's
/// (trust-and-safety.instructions.md, "Course ownership"). This client sees
/// only the courses the reporter has joined, so it can confirm the first case
/// but never the second: a reported user who is a student in none of the
/// reporter's courses may still be one in a course the reporter is not in,
/// where the module files the report instead. Falling back to the reporter's
/// courses here would then point admins at a Safety page the report is not
/// on. So the client never falls back; a report it cannot place still
/// reaches the Safety page, only without a DM.
///
/// A teacher reporting their own student therefore notifies that student's
/// course and none of the teacher's other courses.
List<String> reportCourseIds({
  required String subjectId,
  required String botId,
  required List<CourseRoster> courses,
}) => courses
    .where((c) => c.hasStudent(subjectId, botId: botId))
    .map((c) => c.courseId)
    .toList();

/// The DM a course admin receives about a report: a pointer to the Safety
/// page and nothing else. It never carries the message, the reason or the
/// reported user — the Safety page shows those to the admins entitled to see
/// them, and a DM with the text in it would itself read as the abuse it
/// reports.
Map<String, Object> reportPointerContent(String body) => {
  'msgtype': PangeaEventTypes.report,
  'body': body,
};

/// A course admin a report can be pointed out to, with the course they admin.
class ReportRecipient<T> {
  final T admin;
  final String courseName;

  const ReportRecipient(this.admin, this.courseName);
}

/// How a report ended.
enum ReportOutcome {
  /// The module recorded the report.
  captured,

  /// The module never confirmed it and the reporter chose not to retry. The
  /// failure was already reported to Sentry by [ReportFlow.capture]; the
  /// report stays stored and is replayed on the next start.
  notCaptured,
}

/// "Report message", capture first.
///
/// The module records the report before anything else happens, for every
/// report — offensive or not, whether or not a course admin is found — so no
/// report depends on a teacher lookup succeeding. Only after the module has
/// confirmed it are course admins pointed to the Safety page.
class ReportFlow<T> {
  /// One attempt at sending the report to the module. Reports its own
  /// failures, so a result other than recorded is never silent.
  final Future<CaptureResult> Function(ReportSubmission report) capture;

  /// Stores the report on the device before each attempt, so it is replayed
  /// with the same report id if the app dies before the module confirms it.
  /// Idempotent per report id.
  /// True once the copy is stored.
  final Future<bool> Function(ReportSubmission report) remember;

  /// Drops the stored copy once the module has recorded the report, or once
  /// its id turns out to belong to another report.
  final Future<void> Function(ReportSubmission report) forget;

  /// The id a report moves to after [CaptureResult.conflict] on the given id
  /// (production: [successorReportId]).
  final String Function(String rejectedId) newReportId;

  /// Asks the reporter whether to try again after [capture] failed.
  final Future<bool> Function() offerRetry;

  /// Tells the reporter the report is recorded.
  final void Function() confirmCaptured;

  /// The admins of the report's courses (see [reportCourseIds]).
  final Future<List<ReportRecipient<T>>> Function() lookupCourseAdmins;

  /// Lets the reporter choose who gets the pointer DM; null or empty sends
  /// none.
  final Future<List<ReportRecipient<T>>?> Function(
    List<ReportRecipient<T>> admins,
  )
  selectRecipients;

  /// Sends [content] to [recipient] in a DM.
  final Future<void> Function(
    ReportRecipient<T> recipient,
    Map<String, Object> content,
  )
  sendPointer;

  /// The pointer text for the named course: "A message was reported in
  /// [courseName] — see Safety".
  final String Function(String courseName) pointerBody;

  /// Records a non-offensive report in Sentry.
  final void Function(ReportSubmission report) recordNonOffensive;

  const ReportFlow({
    required this.capture,
    required this.remember,
    required this.forget,
    required this.newReportId,
    required this.offerRetry,
    required this.confirmCaptured,
    required this.lookupCourseAdmins,
    required this.selectRecipients,
    required this.sendPointer,
    required this.pointerBody,
    required this.recordNonOffensive,
  });

  Future<ReportOutcome> run(
    ReportSubmission report, {
    required bool offensive,
  }) async {
    final recorded = await captureWithRetry(report);
    if (recorded == null) return ReportOutcome.notCaptured;
    confirmCaptured();

    if (!offensive) {
      recordNonOffensive(recorded);
      return ReportOutcome.captured;
    }

    final admins = await lookupCourseAdmins();
    if (admins.isEmpty) return ReportOutcome.captured;

    final selected = await selectRecipients(admins);
    if (selected == null) return ReportOutcome.captured;
    for (final recipient in selected) {
      await sendPointer(
        recipient,
        reportPointerContent(pointerBody(recipient.courseName)),
      );
    }
    return ReportOutcome.captured;
  }

  /// Sends [report] until the module records it or the reporter gives up,
  /// and returns the submission the module recorded, or null.
  ///
  /// Every retry carries the same [ReportSubmission.reportId], with one
  /// exception: a [CaptureResult.conflict] means that id is already the
  /// module's for another report, so it can never be recorded under it. The
  /// old id is forgotten — never replayed — and the report continues as a
  /// fresh submission under the id [newReportId] derives from it.
  ///
  /// The report is stored before every attempt and forgotten only once the
  /// module has recorded it, so a report the reporter gives up on — or that
  /// the app is killed in the middle of — is resent on the next start.
  Future<ReportSubmission?> captureWithRetry(ReportSubmission report) async {
    var current = report;
    while (true) {
      await remember(current);
      final result = await capture(current);
      if (result == CaptureResult.recorded) {
        await forget(current);
        return current;
      }
      if (result == CaptureResult.conflict) {
        final fresh = current.withReportId(newReportId(current.reportId));
        // The fresh copy is stored before the old one goes, so the report
        // is on the device at every moment. If it cannot be stored, the old
        // copy stays: a replay meets the same 409 and rotates it there.
        if (await remember(fresh)) await forget(current);
        current = fresh;
      }
      if (!await offerRetry()) return null;
    }
  }
}
