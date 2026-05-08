import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/pangea/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/pangea/join_codes/space_code_controller.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseCodeStepView extends StatefulWidget {
  final CourseCodeOnboardingStep step;
  final VoidCallback onUpdate;
  final Object? error;

  const CourseCodeStepView({
    super.key,
    required this.step,
    required this.onUpdate,
    required this.error,
  });

  @override
  CourseCodeStepViewState createState() => CourseCodeStepViewState();
}

class CourseCodeStepViewState extends State<CourseCodeStepView> {
  late final CourseCodeOnboardingStep _step;

  final TextEditingController _codeController = TextEditingController();

  Timer? _debounce;
  Future<CoursePlanModel> Function(GetLocalizedCoursesRequest)? getCoursePlan;

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    _step.setup(
      CoursePlansRepo.get,
      (code, client) =>
          SpaceCodeController.joinSpaceWithCode(code, client: client),
      (update) => MatrixState.pangeaController.userController.updateProfile(
        update,
        waitForDataInSync: true,
      ),
      _getCourseIdByRoomId,
    );
    _codeController.addListener(_setCourseCode);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _codeController.removeListener(_setCourseCode);
    _codeController.dispose();
    super.dispose();
  }

  void _setCourseCode() {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 300), () {
      _step.setCourseCode(_codeController.text);
      widget.onUpdate();
      _debounce?.cancel();
      _debounce = null;
    });
  }

  Future<String> _getCourseIdByRoomId(String roomId) async {
    final client = _step.client;
    Room? room = client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      try {
        await client.waitForRoomInSync(roomId).timeout(Duration(seconds: 10));
      } catch (e) {
        if (e is! TimeoutException) rethrow;
      }
    }

    room = client.getRoomById(roomId);
    if (room?.coursePlan == null) {
      throw "Room not found or doesn't contain course";
    }

    return room!.coursePlan!.uuid;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 12.0,
      mainAxisSize: MainAxisSize.min,
      children: [
        BotFace(expression: BotExpression.idle, useRive: true, width: 140.0),
        Text(
          widget.error != null
              ? L10n.of(context).courseCodeStepErrorMessage
              : L10n.of(context).courseCodeStepTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: widget.error != null ? theme.colorScheme.error : null,
          ),
        ),
        TextField(
          controller: _codeController,
          decoration: InputDecoration(
            hintText: L10n.of(context).courseCodeStepHint,
            errorText: widget.error != null ? '' : null,
            suffixIcon: widget.error != null
                ? Icon(Icons.error, color: theme.colorScheme.error)
                : null,
          ),
        ),
      ],
    );
  }
}
