import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/access_notice_extension.dart';
import 'package:fluffychat/features/analytics_access/analytics_access_notice_dialog.dart';
import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';

/// The learner declined to share their analytics before joining a course that
/// requires it, so nothing was joined.
class AnalyticsConsentDeclined implements Exception {
  const AnalyticsConsentDeclined();

  @override
  String toString() => 'AnalyticsConsentDeclined: nothing was joined';
}

/// What a module preview says about a course before the join: enough to ask
/// the learner to share their analytics first
/// (course-analytics-access.instructions.md, "Ask before joining").
class CourseJoinPreview {
  final String roomId;

  /// Null when the preview did not carry the course's settings (a server
  /// without them), so the question follows the join instead.
  final bool? requiresSharing;

  /// Joining makes the learner a teacher of the course, who is not asked.
  final bool opensAsTeacher;

  final String? languageCode;
  final Set<String> teacherIds;

  const CourseJoinPreview({
    required this.roomId,
    required this.requiresSharing,
    required this.opensAsTeacher,
    required this.languageCode,
    required this.teacherIds,
  });

  /// One room of the code preview (`preview_with_code`).
  factory CourseJoinPreview.fromCodePreview(Map<String, dynamic> json) {
    final state = json['state_events'];
    Map<String, dynamic>? content(String type) {
      final byStateKey = state is Map ? state[type] : null;
      final event = byStateKey is Map ? byStateKey['default'] : null;
      final content = event is Map ? event['content'] : null;
      return content is Map<String, dynamic> ? content : null;
    }

    final settings = content(PangeaEventTypes.courseSettings);
    final plan = content(PangeaEventTypes.coursePlan);
    final admins = json['admins'];
    return CourseJoinPreview(
      roomId: json['room_id'] as String,
      requiresSharing: settings == null
          ? null
          : CourseSettingsModel.fromJson(settings).requireAnalyticsAccess,
      opensAsTeacher: json['opens_as_admin'] == true,
      languageCode: plan == null ? null : CoursePlanEvent.tryParse(plan)?.l2,
      teacherIds: {
        if (admins is List)
          for (final admin in admins)
            if (admin is Map && admin['user_id'] is String)
              admin['user_id'] as String,
      },
    );
  }

  /// A course known by id (`room_preview`): an invite, an approved knock or a
  /// public course.
  factory CourseJoinPreview.fromRoomSummary(
    String roomId,
    RoomSummaryResponse summary,
    String? userId,
  ) {
    final powerLevels = summary.powerLevels ?? const <String, int>{};
    return CourseJoinPreview(
      roomId: roomId,
      requiresSharing: summary.courseSettings?.requireAnalyticsAccess,
      opensAsTeacher:
          userId != null &&
          (powerLevels[userId] ?? 0) >= SpaceConstants.powerLevelOfAdmin,
      languageCode: summary.coursePlan?.l2,
      teacherIds: summary.adminUserIDs
          .where((id) => id != BotName.byEnvironment)
          .toSet(),
    );
  }
}

/// Asks a learner to share their analytics before joining a course that
/// requires it, so Go back joins nothing
/// (course-analytics-access.instructions.md, "Ask before joining"). An answer
/// is recorded before the join, so the step that runs after it grants without
/// asking again; when no preview can be read, that step still asks.
class AnalyticsConsentBeforeJoin {
  /// One question per course, however many screens reach it at once.
  static final Map<String, Future<bool>> _inFlight = {};

  /// For a code join: every course [code] opens, before the knock. False when
  /// the learner declined.
  static Future<bool> askForCode(
    Client client,
    String code, {
    BuildContext? context,
  }) async {
    final List<CourseJoinPreview> previews;
    try {
      previews = (await client.previewWithCode(
        code,
      )).map(CourseJoinPreview.fromCodePreview).toList();
    } catch (e, s) {
      // The knock that follows reports a code that opens nothing.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"space_code": code},
        level: PangeaHttpException.severityOf(e),
      );
      return true;
    }
    for (final preview in previews) {
      if (!await ask(client, preview, context: context)) return false;
    }
    return true;
  }

  /// For a course known by id. Declining turns an invite down, as its Decline
  /// would, so it does not linger unanswered. False when the learner declined.
  static Future<bool> askForRoom(
    Client client,
    String roomId, {
    BuildContext? context,
  }) async {
    final local = client.getRoomById(roomId);
    if (local != null &&
        (local.membership == Membership.join || !local.isSpace)) {
      return true;
    }

    final CourseJoinPreview preview;
    try {
      final summary = (await client.getRoomSummaries([
        roomId,
      ], l1Code: null)).summaries[roomId];
      if (summary == null) return true;
      preview = CourseJoinPreview.fromRoomSummary(
        roomId,
        summary,
        client.userID,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"room_id": roomId},
        level: PangeaHttpException.severityOf(e),
      );
      return true;
    }

    final proceed = await ask(client, preview, context: context);
    if (!proceed && local?.membership == Membership.invite) {
      await local!.leave();
    }
    return proceed;
  }

  /// True to go on with the join; false when the learner declined.
  static Future<bool> ask(
    Client client,
    CourseJoinPreview preview, {
    BuildContext? context,
    @visibleForTesting BuildContext? Function()? navigatorContext,
  }) {
    final roomId = preview.roomId;
    // A block body: `remove` returns this very future, and whenComplete
    // waits on a returned future, so an arrow body would never complete.
    return _inFlight[roomId] ??=
        _ask(
          client,
          preview,
          context ?? (navigatorContext ?? _appNavigatorContext)(),
        ).whenComplete(() {
          _inFlight.remove(roomId);
        });
  }

  static Future<bool> _ask(
    Client client,
    CourseJoinPreview preview,
    BuildContext? context,
  ) async {
    if (preview.requiresSharing != true || preview.opensAsTeacher) return true;
    if (client.acceptedAccessNotice(preview.roomId)) return true;

    try {
      final lang = client.courseLanguageByCode(preview.languageCode);
      if (lang != null &&
          await client.sharesAnalyticsWith(preview.teacherIds, lang)) {
        await client.setAccessNoticeAccepted(preview.roomId);
        return true;
      }

      // No screen to ask on: the question follows the join.
      if (context == null || !context.mounted) return true;
      final answer = await showDialog<OkCancelResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AnalyticsAccessNoticeDialog(targetLanguage: lang),
      );
      if (answer == OkCancelResult.cancel) return false;

      await client.setAccessNoticeAccepted(preview.roomId);
      return true;
    } catch (e, s) {
      // The step after the join asks again when no answer was recorded.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"room_id": preview.roomId},
        level: PangeaHttpException.severityOf(e),
      );
      return true;
    }
  }

  static BuildContext? _appNavigatorContext() =>
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
}
