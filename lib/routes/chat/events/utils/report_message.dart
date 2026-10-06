import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/utils/report_api_extension.dart';
import 'package:fluffychat/routes/chat/events/utils/report_flow.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

Future<Room> getReportsDM(User teacher, Room space) async {
  final String roomId = await teacher.startDirectChat(enableEncryption: false);
  space.setSpaceChild(roomId, suggested: false);
  return space.client.getRoomById(roomId)!;
}

void reportEvent(
  Event event,
  ChatController controller,
  BuildContext context,
) async {
  final score = await showModalActionPopup<int>(
    context: context,
    title: L10n.of(context).reportMessage,
    message: L10n.of(context).whyDoYouWantToReportThis,
    cancelLabel: L10n.of(context).cancel,
    actions: [
      AdaptiveModalAction(value: 1, label: L10n.of(context).offensive),
      AdaptiveModalAction(value: 2, label: L10n.of(context).other),
    ],
  );
  if (score == null || !context.mounted) return;

  final reason = await showTextInputDialog(
    context: context,
    title: L10n.of(context).whyDoYouWantToReportThis,
    okLabel: L10n.of(context).ok,
    cancelLabel: L10n.of(context).cancel,
    hintText: L10n.of(context).reason,
    autoSubmit: true,
    validator: (text) {
      if (text.isEmpty) {
        return L10n.of(context).pleaseFillOut;
      }
      return null;
    },
  );

  if (reason == null) return;

  // From here the report must outlive the chat screen: leaving the chat while
  // it is being sent would otherwise take the retry prompt with it. The root
  // navigator stays mounted for as long as the app runs.
  final flowContext =
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
      context;

  final timeline = controller.timeline;
  final report = ReportSubmission(
    // Generated once here and reused by every retry below.
    reportId: const Uuid().v4(),
    roomId: event.room.id,
    eventId: timeline == null
        // No timeline means no edits are loaded either, so what the reporter
        // sees is the event itself.
        ? event.eventId
        : displayedRevisionId(event, timeline),
    reason: reason,
  );

  final client = Matrix.of(flowContext).client;
  final l10n = L10n.of(flowContext);
  await ReportFlow<SpaceTeacher>(
    capture: (report) => _captureReport(flowContext, client, report),
    offerRetry: () => _offerReportRetry(flowContext, report),
    confirmCaptured: () {
      if (!flowContext.mounted) return;
      ScaffoldMessenger.of(
        flowContext,
      ).showSnackBarAnnounced(SnackBar(content: Text(l10n.reportSent)));
    },
    lookupCourseAdmins: () => _lookupCourseAdmins(flowContext, client, event),
    selectRecipients: (admins) async {
      if (!flowContext.mounted) return null;
      final selected = await showDialog<List<SpaceTeacher>>(
        context: flowContext,
        useRootNavigator: false,
        builder: (BuildContext context) => TeacherSelectDialog(
          teachers: admins.map((admin) => admin.admin).toList(),
        ),
      );
      return selected
          ?.map((teacher) => ReportRecipient(teacher, teacher.courseName))
          .toList();
    },
    sendPointer: (recipient, content) async {
      if (!flowContext.mounted) return;
      await showFutureLoadingDialog(
        context: flowContext,
        future: () async {
          final dm = await getReportsDM(
            recipient.admin.teacher,
            recipient.admin.space,
          );
          await dm.sendEvent(content);
        },
      );
    },
    pointerBody: l10n.reportPointerMessage,
    recordNonOffensive: recordNonOffensiveReport,
  ).run(report, offensive: score == 1);
}

/// Sends [report] to the module behind a loading dialog; true once recorded.
///
/// A failure is reported to Sentry here, exactly once per attempt, with ids
/// only — never the reason, which is the reporter's own words.
Future<bool> _captureReport(
  BuildContext context,
  Client client,
  ReportSubmission report,
) async {
  Future<Object?> attempt() async {
    try {
      await client.captureReport(report);
      return null;
    } catch (e, s) {
      await ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'report_id': report.reportId,
          'room_id': report.roomId,
          'event_id': report.eventId,
        },
      );
      return e;
    }
  }

  if (!context.mounted) return await attempt() == null;
  final result = await showFutureLoadingDialog<Object?>(
    context: context,
    future: attempt,
  );
  return !result.isError && result.result == null;
}

/// Tells the reporter the report was not sent and asks whether to retry.
Future<bool> _offerReportRetry(
  BuildContext context,
  ReportSubmission report,
) async {
  if (!context.mounted) {
    // Only reachable while the app itself is going away. The failed attempt
    // is already in Sentry; this records that it was also the last one.
    await ErrorHandler.logError(
      e: 'A report was not recorded and there was no screen to offer a retry on',
      data: {
        'report_id': report.reportId,
        'room_id': report.roomId,
        'event_id': report.eventId,
      },
    );
    return false;
  }
  final l10n = L10n.of(context);
  final answer = await showOkCancelAlertDialog(
    context: context,
    title: l10n.reportMessage,
    message: l10n.reportNotSent,
    okLabel: l10n.tryAgain,
    cancelLabel: l10n.cancel,
  );
  return answer == OkCancelResult.ok;
}

/// The non-bot admins of the report's courses ([reportCourseIds]), other than
/// the reporter, each once.
Future<List<ReportRecipient<SpaceTeacher>>> _lookupCourseAdmins(
  BuildContext context,
  Client client,
  Event event,
) async {
  // The reporter has left the chat: there is nowhere to ask whom to notify.
  // The report itself is already recorded, so this skips only the pointer DM.
  if (!context.mounted) return const [];
  final result = await showFutureLoadingDialog<List<SpaceTeacher>>(
    context: context,
    future: () => getReportTeachers(client, event.senderId),
  );
  return (result.result ?? const <SpaceTeacher>[])
      .map((teacher) => ReportRecipient(teacher, teacher.courseName))
      .toList();
}

/// Records a non-offensive report in Sentry: which event, never what it says
/// or why it was reported. The report itself is on the Safety page.
void recordNonOffensiveReport(ReportSubmission report) {
  Sentry.addBreadcrumb(
    Breadcrumb(
      data: {
        'eventID': report.eventId,
        'roomID': report.roomId,
        'reportID': report.reportId,
      },
    ),
  );
  Sentry.captureException(
    'User reported message with eventId ${report.eventId}',
    stackTrace: StackTrace.current,
    withScope: (scope) {
      scope.fingerprint = ['user-report', report.eventId];
    },
  );
}

/// The non-bot admins of the courses a report about [subjectId] belongs to
/// ([reportCourseIds]), excluding the reporter, each listed once with the
/// first such course.
Future<List<SpaceTeacher>> getReportTeachers(
  Client client,
  String subjectId,
) async {
  final reporterId = client.userID;
  if (reporterId == null) return const [];

  final courses = client.rooms
      .where(
        (room) =>
            room.membership == Membership.join &&
            room.getState(PangeaEventTypes.coursePlan) != null,
      )
      .toList();

  final rosters = <String, CourseRoster>{};
  final admins = <String, List<User>>{};
  for (final course in courses) {
    final members = await course.requestParticipants([Membership.join]);
    rosters[course.id] = CourseRoster(
      courseId: course.id,
      joinedPowerLevels: {for (final m in members) m.id: m.powerLevel},
    );
    admins[course.id] = members
        .where((m) => m.powerLevel >= 100 && m.id != BotName.byEnvironment)
        .toList();
  }

  final courseIds = reportCourseIds(
    subjectId: subjectId,
    botId: BotName.byEnvironment,
    courses: rosters.values.toList(),
  );

  final teachers = <SpaceTeacher>[];
  for (final courseId in courseIds) {
    final course = courses.firstWhere((room) => room.id == courseId);
    for (final admin in admins[courseId]!) {
      if (admin.id == reporterId) continue;
      if (teachers.any((t) => t.teacher.id == admin.id)) continue;
      teachers.add(SpaceTeacher(admin, course));
    }
  }
  return teachers;
}

class TeacherSelectDialog extends StatefulWidget {
  final List<SpaceTeacher> teachers;
  const TeacherSelectDialog({super.key, required this.teachers});

  @override
  State<StatefulWidget> createState() => _TeacherSelectDialogState();
}

class _TeacherSelectDialogState extends State<TeacherSelectDialog> {
  final List<SpaceTeacher> _selectedItems = [];

  void _itemChange(SpaceTeacher itemValue, bool isSelected) {
    setState(() {
      isSelected
          ? _selectedItems.add(itemValue)
          : _selectedItems.remove(itemValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        L10n.of(context).reportToTeacher,
        style: const TextStyle(fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: widget.teachers
              .map(
                (teacher) => CheckboxListTile(
                  value: _selectedItems.contains(teacher),
                  title: Text(teacher.teacher.id),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (isChecked) => _itemChange(teacher, isChecked!),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_selectedItems),
          child: Text(L10n.of(context).submit),
        ),
      ],
    );
  }
}

class SpaceTeacher {
  final User teacher;
  final Room space;

  SpaceTeacher(this.teacher, this.space);

  String get courseName => space.getLocalizedDisplayname();
}
