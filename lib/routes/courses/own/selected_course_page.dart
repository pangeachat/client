import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as sdk;

import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/courses/own/selected_course_view.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum SelectedCourseMode { launch, addToSpace }

class SelectedCourse extends StatefulWidget {
  final String courseId;
  final SelectedCourseMode mode;

  /// In addToSpace mode, the ID of the space to add the course to.
  /// In join mode, the ID of the space to join that already has this course.
  final String? spaceId;

  final Widget? closeButton;

  const SelectedCourse(
    this.courseId,
    this.mode, {
    super.key,
    this.spaceId,
    this.closeButton,
  });

  @override
  SelectedCourseController createState() => SelectedCourseController();
}

class SelectedCourseController extends State<SelectedCourse> {
  late final QuestObjectivesLoader _objectivesProvider;

  @override
  initState() {
    super.initState();
    _objectivesProvider = QuestObjectivesLoader(
      client: Matrix.of(context).client,
    );
    _objectivesProvider.loadOutline(widget.courseId);
  }

  @override
  void didUpdateWidget(covariant SelectedCourse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId) {
      _objectivesProvider.loadOutline(widget.courseId);
    }
  }

  @override
  void dispose() {
    _objectivesProvider.dispose();
    super.dispose();
  }

  QuestObjectivesLoader get objectivesProvider => _objectivesProvider;

  String get title {
    switch (widget.mode) {
      case SelectedCourseMode.launch:
        return L10n.of(context).newCourse;
      case SelectedCourseMode.addToSpace:
        return L10n.of(context).addCoursePlan;
    }
  }

  String get buttonText {
    switch (widget.mode) {
      case SelectedCourseMode.launch:
        return L10n.of(context).createCourse;
      case SelectedCourseMode.addToSpace:
        return L10n.of(context).addCoursePlan;
    }
  }

  Future<void> submit(QuestPlan course) async {
    switch (widget.mode) {
      case SelectedCourseMode.launch:
        return launchCourse(widget.courseId, course);
      case SelectedCourseMode.addToSpace:
        return addCourseToSpace(course);
    }
  }

  Future<void> launchCourse(String courseId, QuestPlan course) async {
    final client = Matrix.of(context).client;
    final Completer<String> completer = Completer<String>();
    client
        .createPangeaSpace(
          name: course.name,
          topic: course.description,
          visibility: sdk.Visibility.public,
          joinRules: sdk.JoinRules.knock,
          initialState: [
            sdk.StateEvent(
              type: PangeaEventTypes.coursePlan,
              content: CoursePlanEvent(
                uuid: courseId,
                l2: course.targetLanguage,
              ).toJson(),
            ),
            sdk.StateEvent(
              type: PangeaEventTypes.courseSettings,
              content: CourseSettingsModel(
                requireAnalyticsAccess: true,
              ).toJson(),
            ),
          ],
          spaceChild: 0,
        )
        .then((spaceId) => completer.complete(spaceId))
        .catchError((error) => completer.completeError(error));

    context.go(
      WorkspaceNav.openAddCoursePage(
        GoRouterState.of(context).uri,
        AddCourseSubpageEnum.own,
        createCourseId: widget.courseId,
        showNewCourseInvitePage: true,
      ),
      extra: completer,
    );
  }

  Future<void> addCourseToSpace(QuestPlan course) async {
    if (widget.spaceId == null) {
      throw Exception("Space ID is null");
    }

    final space = Matrix.of(context).client.getRoomById(widget.spaceId!);

    if (space == null) {
      throw Exception("Space not found");
    }

    await space.addCourseToSpace(
      widget.courseId,
      targetLanguage: course.targetLanguage,
    );

    if (space.name.isEmpty) {
      await space.setName(course.name);
    }

    if (space.topic.isEmpty) {
      await space.setDescription(course.description);
    }

    if (!mounted) return;
    context.go(
      WorkspaceNav.openCourse(
        GoRouterState.of(context).uri,
        space.id,
        tab: SpaceSettingsTabs.course,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SelectedCourseView(this);
}
