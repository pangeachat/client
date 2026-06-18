import 'package:flutter/material.dart';

import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'course_plans_repo.dart';

mixin CoursePlanProvider<T extends StatefulWidget> on State<T> {
  bool loadingCourse = true;
  Object? courseError;

  bool loadingTopics = false;
  Object? topicError;

  CoursePlanModel? course;

  Future<void> _initStorage() async {
    final futures = [
      GetStorage.init("course_storage"),
      GetStorage.init("course_activity_storage"),
      GetStorage.init("course_location_media_storage"),
      GetStorage.init("course_location_storage"),
      GetStorage.init("course_media_storage"),
      GetStorage.init("course_topic_storage"),
    ];

    await Future.wait(futures);
  }

  Future<void> loadCourse(String courseId) async {
    await _initStorage();
    if (!mounted) return;
    setState(() {
      loadingCourse = true;
      courseError = null;
      course = null;
    });

    final request = GetLocalizedCoursesRequest(
      coursePlanIds: [courseId],
      l1: MatrixState.pangeaController.userController.userL1Code!,
    );

    try {
      course = await CoursePlansRepo.get(request);
      await course!.fetchMediaUrls();
    } catch (e, s) {
      // Course id-space is shared with the v3 ``quest-plans`` collection,
      // so an id that 404s in v1 may still resolve in v3 — fall back before
      // surfacing the error. The synthesized model omits ``mediaIds`` /
      // ``topicIds`` so ``fetchMediaUrls`` / ``loadTopics`` are no-ops; the
      // Course Plan tab renders via [QuestRepo.outline] using this id.
      final quest = await QuestPlansRepo.get(courseId);
      if (quest != null) {
        course = quest;
      } else {
        if (e is MissingCourseTranslationException) {
          ErrorHandler.logError(
            e: e.errorMessage,
            s: s,
            data: {
              'request': request.toJson(),
              'responseCourseIds': e.response.coursePlans.keys.toList(),
            },
          );
        } else {
          ErrorHandler.logError(e: e, s: s, data: request.toJson());
        }
        courseError = e;
      }
    } finally {
      if (mounted) setState(() => loadingCourse = false);
    }
  }

  Future<void> loadTopics() async {
    if (!mounted) return;
    setState(() {
      loadingTopics = true;
      topicError = null;
    });

    try {
      if (course == null) {
        throw Exception("Course is null");
      }

      // Quest-synthesized models carry placeholder topic ids of the form
      // ``quest:<questId>:mission:<i>`` purely so the "N modules" chip
      // reads correctly. They do NOT resolve in the v1 ``course-plan-topics``
      // collection, so skip the v1 topic fan-out — the Course Plan tab
      // renders from [QuestRepo.outline] using the course's uuid (the v3
      // quest id) instead.
      final isQuestSynthesized = course!.topicIds.isNotEmpty &&
          course!.topicIds.first.startsWith('quest:');
      if (isQuestSynthesized) {
        return;
      }

      await course!.fetchTopics();
      await _loadTopicsMedia();
    } catch (e) {
      topicError = e;
    } finally {
      if (mounted) setState(() => loadingTopics = false);
    }
  }

  Future<void> _loadTopicsMedia() async {
    final List<Future> futures = [];
    if (course == null) return;
    for (final topicId in course!.topicIds) {
      final topic = course!.loadedTopics[topicId];
      if (topic != null) {
        futures.add(topic.fetchLocationMedia());
      }
    }
    await Future.wait(futures);
  }
}
