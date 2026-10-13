import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/utils/pending_reports.dart';
import 'package:fluffychat/routes/chat/events/utils/report_api_extension.dart';
import 'package:fluffychat/routes/chat/events/utils/report_flow.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The DM a report pointer goes to: one holding exactly the reporter and
/// [teacher], filed under [space].
Future<Room> getReportsDM(User teacher, Room space) async {
  final client = space.client;
  final roomId = await reportDmRoomId(
    existingRoomId: client.getDirectChatFromUserId(teacher.id),
    reporterId: client.userID!,
    adminId: teacher.id,
    membersOf: (roomId) async {
      final room = client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) return null;
      return currentJoinedOrInvited(client, roomId);
    },
    createFresh: () => client.startDirectChat(
      teacher.id,
      enableEncryption: false,
      skipExistingChat: true,
    ),
  );
  space.setSpaceChild(roomId, suggested: false);
  return client.getRoomById(roomId)!;
}

/// Who is joined to or invited into [roomId], as the homeserver has it now.
///
/// Asked of the server rather than read from the local member list, which
/// the SDK serves from cache when it looks complete — and so would miss an
/// invite that has not synced yet.
@visibleForTesting
Future<Set<String>> currentJoinedOrInvited(MatrixApi api, String roomId) async {
  final events = await api.getMembersByRoom(roomId) ?? const [];
  return events
      .where(
        (e) =>
            e.content['membership'] == Membership.join.name ||
            e.content['membership'] == Membership.invite.name,
      )
      .map((e) => e.stateKey)
      .nonNulls
      .toSet();
}

/// The room to send a report pointer to [adminId] in.
///
/// The account's existing direct chat with the admin is reused only when its
/// joined and invited members are exactly the reporter and that admin. A
/// direct chat can gain members — anyone in it can invite another teacher —
/// and the pointer must reach only the admins of the report's courses, so
/// anything else gets a fresh DM. [membersOf] returns null for a room the
/// reporter is not joined to.
Future<String> reportDmRoomId({
  required String? existingRoomId,
  required String reporterId,
  required String adminId,
  required Future<Set<String>?> Function(String roomId) membersOf,
  required Future<String> Function() createFresh,
}) async {
  if (existingRoomId != null) {
    final members = await membersOf(existingRoomId);
    if (members != null &&
        members.length == 2 &&
        members.contains(reporterId) &&
        members.contains(adminId)) {
      return existingRoomId;
    }
  }
  return createFresh();
}

void reportEvent(
  Event event,
  ChatController controller,
  BuildContext context,
) => submitReport(
  event: event,
  timeline: controller.timeline,
  context: context,
  client: Matrix.of(context).client,
  // From the reason onward the report must outlive the chat screen: leaving
  // the chat while it is being sent would otherwise take the retry prompt
  // with it. The root navigator stays mounted for as long as the app runs.
  flowContext: () =>
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext,
);

/// "Report message", from the reporter's first tap to the teacher pointer.
/// The production wiring of [ReportFlow]; [reportEvent] only supplies the
/// chat's timeline, client and root navigator.
@visibleForTesting
Future<ReportOutcome?> submitReport({
  required Event event,
  required Timeline? timeline,
  required BuildContext context,
  required Client client,
  required BuildContext? Function() flowContext,
  PendingReportStore? store,
}) async {
  // Resolved now, while the chat is open: the timeline that holds the edits
  // is cleared when the chat closes, which can happen while the dialogs
  // below wait for the reporter.
  final reportedEventId = timeline == null
      // No timeline means no edits are loaded either, so what the reporter
      // sees is the event itself.
      ? event.eventId
      : displayedRevisionId(event, timeline);
  final reporterId = client.userID;
  if (reporterId == null) return null;

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
  if (score == null || !context.mounted) return null;

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

  if (reason == null) return null;

  final uiContext = flowContext() ?? context;
  // The workspace's own messenger owns the chat Scaffolds; the root one, which
  // the root navigator would resolve, has none to show a snackbar on. It lives
  // in the workspace shell, so it outlasts the chat screen too.
  final messenger = context.mounted ? ScaffoldMessenger.maybeOf(context) : null;

  final report = ReportSubmission(
    // Generated once here and reused by every retry, and by the replay on a
    // later start if the module never confirms it.
    reportId: const Uuid().v4(),
    roomId: event.room.id,
    eventId: reportedEventId,
    reason: reason,
  );

  final l10n = L10n.of(uiContext);
  Future<PendingReportStore> pending() async =>
      store ?? await PendingReportStore.open();
  return ReportFlow<SpaceTeacher>(
    capture: (report) => _captureReport(uiContext, client, report),
    remember: (report) => _storeSafely(
      () async => (await pending()).remember(reporterId, report),
      report,
      'remember',
    ),
    forget: (report) => _storeSafely(
      () async => (await pending()).forget(reporterId, report.reportId),
      report,
      'forget',
    ),
    newReportId: () => const Uuid().v4(),
    offerRetry: () => _offerReportRetry(uiContext, report),
    confirmCaptured: () {
      if (messenger == null || !messenger.mounted) return;
      messenger.showSnackBarAnnounced(SnackBar(content: Text(l10n.reportSent)));
    },
    lookupCourseAdmins: () => _lookupCourseAdmins(uiContext, client, event),
    selectRecipients: (admins) async {
      if (!uiContext.mounted) return null;
      final selected = await showDialog<List<SpaceTeacher>>(
        context: uiContext,
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
      if (!uiContext.mounted) return;
      await showFutureLoadingDialog(
        context: uiContext,
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

/// Runs a pending-report store operation. A failure is reported and never
/// stops the report from being sent: refusing to send because the device
/// could not keep a backup copy would lose more reports than it saves. The
/// write is tried again before every attempt.
Future<void> _storeSafely(
  Future<void> Function() write,
  ReportSubmission report,
  String operation,
) async {
  try {
    await write();
  } catch (e, s) {
    await ErrorHandler.logError(
      e: e,
      s: s,
      data: {
        'where': 'PendingReportStore.$operation',
        'report_id': report.reportId,
      },
    );
  }
}

/// One attempt at recording [report], behind a progress dialog.
Future<CaptureResult> _captureReport(
  BuildContext context,
  Client client,
  ReportSubmission report,
) {
  final attempt = attemptReportCapture(client, report);
  if (!context.mounted) return attempt;
  return showReportProgress(context, attempt);
}

/// Shows a progress dialog over [pending] and returns its result.
///
/// The outcome is [pending]'s own, never the dialog's: the dialog cannot be
/// dismissed (no barrier tap, no Back), and it removes exactly its own route
/// when [pending] settles. A dismissible loading dialog would let Back read as
/// a failure while the request is still in flight, open the retry prompt, and
/// then have the late completion pop that prompt instead.
@visibleForTesting
Future<T> showReportProgress<T>(BuildContext context, Future<T> pending) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final label = L10n.of(context).loadingPleaseWait;
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog.adaptive(
        content: Row(
          children: [
            const CircularProgressIndicator.adaptive(),
            const SizedBox(width: 20),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  navigator.push(route);
  try {
    return await pending;
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
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

/// [roomId]'s joined members and their power levels, as the homeserver has
/// them now.
@visibleForTesting
Future<CourseRoster> courseRosterFromServer(
  MatrixApi api,
  String roomId,
) async {
  final members = await api.getMembersByRoom(
    roomId,
    membership: Membership.join,
  );
  final powerLevels = await api.getRoomStateWithKey(
    roomId,
    EventTypes.RoomPowerLevels,
    '',
  );
  final users = powerLevels['users'];
  final usersDefault = powerLevels['users_default'];
  int levelOf(String userId) {
    final level = users is Map ? users[userId] : null;
    if (level is int) return level;
    return usersDefault is int ? usersDefault : 0;
  }

  return CourseRoster(
    courseId: roomId,
    joinedPowerLevels: {
      for (final e in members ?? const <MatrixEvent>[])
        if (e.content['membership'] == Membership.join.name &&
            e.stateKey != null)
          e.stateKey!: levelOf(e.stateKey!),
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

  // Read from the homeserver, not the local cache: an admin removed or
  // demoted moments ago must not be offered the pointer before /sync
  // catches up.
  final rosters = <String, CourseRoster>{};
  for (final course in courses) {
    rosters[course.id] = await courseRosterFromServer(client, course.id);
  }

  final courseIds = reportCourseIds(
    subjectId: subjectId,
    botId: BotName.byEnvironment,
    courses: rosters.values.toList(),
  );

  final teachers = <SpaceTeacher>[];
  for (final courseId in courseIds) {
    final course = courses.firstWhere((room) => room.id == courseId);
    final admins = rosters[courseId]!.joinedPowerLevels.entries
        .where((m) => m.value >= 100 && m.key != BotName.byEnvironment)
        .map((m) => m.key);
    for (final adminId in admins) {
      if (adminId == reporterId) continue;
      if (teachers.any((t) => t.teacher.id == adminId)) continue;
      teachers.add(SpaceTeacher(User(adminId, room: course), course));
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
