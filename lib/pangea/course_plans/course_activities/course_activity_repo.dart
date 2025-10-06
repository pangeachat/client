import 'dart:async';

import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/course_activities_image_urls_request.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/course_activities_image_urls_response.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/course_activities_response.dart';
import 'package:fluffychat/pangea/course_plans/course_info_batch_request.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan_activity.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan_activity_media.dart';
import 'package:fluffychat/pangea/payload_client/payload_client.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseActivityRepo {
  static final Map<String, Completer<CourseActivitiesResponse>> _cache = {};
  static final GetStorage _storage = GetStorage('course_activity_storage');

  static Future<CourseActivitiesResponse> get(
    CourseInfoBatchRequest request,
  ) async {
    final activities = <ActivityPlanModel>[];

    await _storage.initStorage;
    activities.addAll(getCached(request).activities);

    final toFetch = request.uuids
        .where((id) => activities.indexWhere((a) => a.activityId == id) == -1)
        .toList();

    if (toFetch.isNotEmpty) {
      final fetchedActivities = await _fetch(
        CourseInfoBatchRequest(
          batchId: request.batchId,
          uuids: toFetch,
        ),
      );
      activities.addAll(fetchedActivities.activities);
      await _setCached(fetchedActivities);
    }

    return CourseActivitiesResponse(activities: activities);
  }

  static Future<CourseActivitiesResponse> _fetch(
    CourseInfoBatchRequest request,
  ) async {
    if (_cache.containsKey(request.batchId)) {
      return _cache[request.batchId]!.future;
    }

    final completer = Completer<CourseActivitiesResponse>();
    _cache[request.batchId] = completer;

    final where = {
      "id": {"in": request.uuids.join(",")},
    };
    final limit = request.uuids.length;

    try {
      final PayloadClient payload = PayloadClient(
        baseUrl: Environment.cmsApi,
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );

      final cmsCoursePlanActivitiesResult = await payload.find(
        CmsCoursePlanActivity.slug,
        CmsCoursePlanActivity.fromJson,
        where: where,
        limit: limit,
        page: 1,
        sort: "createdAt",
      );

      final imageUrls = await _fetchImageUrls(
        CourseActivitiesImageUrlsRequest.fromCmsResponse(
          cmsCoursePlanActivitiesResult,
        ),
      );

      final response = CourseActivitiesResponse.fromCmsResponse(
        cmsCoursePlanActivitiesResult,
        imageUrls,
      );

      completer.complete(response);
      return response;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _cache.remove(request.batchId);
    }
  }

  static Future<CourseActivitiesImageUrlsResponse> _fetchImageUrls(
    CourseActivitiesImageUrlsRequest request,
  ) async {
    final mediaIdsToActivityIds = request.mediaIdsToActivityIds;
    final mediaIds = mediaIdsToActivityIds.keys.whereType<String>().toList();

    if (mediaIds.isEmpty) {
      return CourseActivitiesImageUrlsResponse(imageUrls: {});
    }

    final where = {
      "id": {"in": mediaIds.join(",")},
    };
    final limit = mediaIds.length;

    final PayloadClient payload = PayloadClient(
      baseUrl: Environment.cmsApi,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    final cmsCoursePlanActivityMediasResult = await payload.find(
      CmsCoursePlanActivityMedia.slug,
      CmsCoursePlanActivityMedia.fromJson,
      where: where,
      limit: limit,
      page: 1,
      sort: "createdAt",
    );

    return CourseActivitiesImageUrlsResponse.fromCmsResponse(
      cmsCoursePlanActivityMediasResult,
      mediaIdsToActivityIds,
    );
  }

  static CourseActivitiesResponse getCached(
    CourseInfoBatchRequest request,
  ) {
    final List<ActivityPlanModel> activities = [];
    for (final id in request.uuids) {
      final sentActivityFeedback = sentFeedback[id];
      if (sentActivityFeedback != null &&
          DateTime.now().difference(sentActivityFeedback) >
              const Duration(minutes: 15)) {
        _storage.remove(id);
        _clearSentFeedback(id);
        continue;
      }

      final json = _storage.read<Map<String, dynamic>>(id);
      if (json != null) {
        try {
          final activity = ActivityPlanModel.fromJson(json);
          activities.add(activity);
        } catch (e) {
          // ignore invalid cached data
          _storage.remove(id);
        }
      }
    }

    return CourseActivitiesResponse(activities: activities);
  }

  static Future<void> _setCached(CourseActivitiesResponse activities) async {
    final List<Future> futures = [];
    for (final activity in activities.activities) {
      futures.add(_storage.write(activity.activityId, activity.toJson()));
    }
    await Future.wait(futures);
  }

  static Future<void> clearCache() async {
    await _storage.erase();
  }

  static Map<String, DateTime> get sentFeedback {
    final entry = _storage.read("sent_feedback");
    if (entry != null && entry is Map<String, dynamic>) {
      try {
        return Map<String, DateTime>.from(
          entry.map((key, value) => MapEntry(key, DateTime.parse(value))),
        );
      } catch (e) {
        _storage.remove("sent_feedback");
      }
    }
    return {};
  }

  static Future<void> setSentFeedback(String activityId) async {
    final currentValue = sentFeedback;
    currentValue[activityId] = DateTime.now();
    await _storage.write(
      "sent_feedback",
      currentValue.map((key, value) => MapEntry(key, value.toIso8601String())),
    );
  }

  static Future<void> _clearSentFeedback(String activityId) async {
    final currentValue = sentFeedback;
    currentValue.remove(activityId);
    await _storage.write(
      "sent_feedback",
      currentValue.map((key, value) => MapEntry(key, value.toIso8601String())),
    );
  }
}
