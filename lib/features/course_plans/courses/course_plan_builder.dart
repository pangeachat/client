import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Loads a course for its detail/preview surfaces. world_v2: a course IS a v3
/// quest-plan — [QuestPlansRepo] resolves the id into a [CoursePlanModel] and
/// the Course Plan renders from [QuestRepo.outline]. There is no v1
/// course-plans data layer (topics/media) anymore.
mixin CoursePlanProvider<T extends StatefulWidget> on State<T> {
  bool loadingCourse = true;
  Object? courseError;

  CoursePlanModel? course;

  Future<void> loadCourse(String courseId) async {
    if (!mounted) return;
    setState(() {
      loadingCourse = true;
      courseError = null;
      course = null;
    });

    try {
      final quest = await QuestPlansRepo.get(courseId);
      if (quest == null) {
        throw Exception('No quest plan found for course id $courseId');
      }
      course = quest;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'courseId': courseId});
      courseError = e;
    } finally {
      if (mounted) setState(() => loadingCourse = false);
    }
  }
}
