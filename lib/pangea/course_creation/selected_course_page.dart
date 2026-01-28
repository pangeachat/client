import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/chat_settings/utils/room_summary_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/course_creation/selected_course_view.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/activity_summaries_provider.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_builder.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/join_codes/space_code_controller.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum SelectedCourseMode { launch, addToSpace, join }

class SelectedCourse extends StatefulWidget {
  final String courseId;
  final SelectedCourseMode mode;

  /// In addToSpace mode, the ID of the space to add the course to.
  /// In join mode, the ID of the space to join that already has this course.
  final String? spaceId;

  /// In join mode, the room info for the space that already has this course.
  final String? roomID;

  const SelectedCourse(
    this.courseId,
    this.mode, {
    super.key,
    this.spaceId,
    this.roomID,
  });

  @override
  SelectedCourseController createState() => SelectedCourseController();
}

class SelectedCourseController extends State<SelectedCourse>
    with CoursePlanProvider, ActivitySummariesProvider {
  RoomSummaryResponse? _roomSummary;

  @override
  initState() {
    super.initState();
    _loadSummary();
    loadCourse(widget.courseId).then((_) => loadTopics());
  }

  @override
  void didUpdateWidget(covariant SelectedCourse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId ||
        widget.roomID != oldWidget.roomID) {
      _loadSummary();
      loadCourse(widget.courseId).then((_) => loadTopics());
    }
  }

  String get title {
    switch (widget.mode) {
      case SelectedCourseMode.launch:
        return L10n.of(context).newCourse;
      case SelectedCourseMode.addToSpace:
        return L10n.of(context).addCoursePlan;
      case SelectedCourseMode.join:
        return L10n.of(context).joinWithClassCode;
    }
  }

  String get buttonText {
    switch (widget.mode) {
      case SelectedCourseMode.launch:
        return L10n.of(context).createCourse;
      case SelectedCourseMode.addToSpace:
        return L10n.of(context).addCoursePlan;
      case SelectedCourseMode.join:
        return _roomSummary?.joinRule == JoinRules.knock
            ? L10n.of(context).knock
            : L10n.of(context).join;
    }
  }

  bool get showCodeField =>
      widget.mode == SelectedCourseMode.join &&
      _roomSummary?.joinRule == JoinRules.knock;

  Future<void> _loadSummary() async {
    if (widget.roomID == null) return;
    try {
      await loadRoomSummaries([widget.roomID!]);
      if (roomSummaries == null ||
          !roomSummaries!.containsKey(widget.roomID!)) {
        throw Exception("Room summary not found");
      }

      if (mounted) {
        setState(() => _roomSummary = roomSummaries![widget.roomID!]);
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomID': widget.roomID},
      );
    }
  }

  Future<void> joinWithCode(String code) async {
    if (code.isEmpty) {
      return;
    }

    final roomId = await SpaceCodeController.joinSpaceWithCode(
      context,
      code,
    );

    if (roomId != null) {
      final room = Matrix.of(context).client.getRoomById(roomId);
      room?.isSpace ?? true
          ? context.go('/rooms/spaces/$roomId/details')
          : context.go('/rooms/$roomId');
    }
  }

  Future<void> submit(CoursePlanModel course) async {
    switch (widget.mode) {
      case SelectedCourseMode.launch:
        return launchCourse(widget.courseId, course);
      case SelectedCourseMode.addToSpace:
        return addCourseToSpace(course);
      case SelectedCourseMode.join:
        return joinCourse();
    }
  }

  Future<void> launchCourse(
    String courseId,
    CoursePlanModel course,
  ) async {
    final client = Matrix.of(context).client;
    final Completer<String> completer = Completer<String>();
    client
        .createPangeaSpace(
          name: course.title,
          topic: course.description,
          visibility: sdk.Visibility.public,
          joinRules: sdk.JoinRules.knock,
          initialState: [
            sdk.StateEvent(
              type: PangeaEventTypes.coursePlan,
              content: {
                "uuid": courseId,
              },
            ),
          ],
          avatarUrl: course.imageUrl.toString(),
          spaceChild: 0,
        )
        .then((spaceId) => completer.complete(spaceId))
        .catchError((error) => completer.completeError(error));

    context.go(
      "/rooms/course/own/${widget.courseId}/invite",
      extra: completer,
    );
  }

  Future<void> addCourseToSpace(CoursePlanModel course) async {
    if (widget.spaceId == null) {
      throw Exception("Space ID is null");
    }

    final space = Matrix.of(context).client.getRoomById(widget.spaceId!);

    if (space == null) {
      throw Exception("Space not found");
    }

    await space.addCourseToSpace(widget.courseId);

    if (space.name.isEmpty) {
      await space.setName(course.title);
    }

    if (space.topic.isEmpty) {
      await space.setDescription(course.description);
    }

    if (!mounted) return;
    context.go("/rooms/spaces/${space.id}/details?tab=course");
  }

  Future<void> joinCourse() async {
    if (widget.roomID == null) {
      throw Exception("Room chunk is null");
    }

    final roomID = widget.roomID!;

    final client = Matrix.of(context).client;
    final r = client.getRoomById(roomID);
    if (r != null && r.membership == Membership.join) {
      if (mounted) {
        context.go("/rooms/spaces/${r.id}/details");
      }
      return;
    }

    final knock = _roomSummary?.joinRule == JoinRules.knock;
    final roomId = widget.roomID != null && knock
        ? await client.knockRoom(widget.roomID!)
        : await client.joinRoom(widget.roomID!);

    Room? room = client.getRoomById(roomId);
    if (!knock && room?.membership != Membership.join) {
      await client.waitForRoomInSync(roomId, join: true);
      room = client.getRoomById(roomId);
    }

    if (knock) {
      Navigator.of(context).pop();
      await showOkAlertDialog(
        context: context,
        title: L10n.of(context).youHaveKnocked,
        message: L10n.of(context).knockDesc,
      );
      return;
    }

    if (room == null) {
      throw Exception("Failed to join room");
    }

    if (mounted) {
      context.go("/rooms/spaces/$roomId/details");
    }
  }

  @override
  Widget build(BuildContext context) => SelectedCourseView(this);
}
