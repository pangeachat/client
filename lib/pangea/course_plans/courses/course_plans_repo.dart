import 'dart:async';
import 'dart:convert';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/course_activity_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_locations/course_location_media_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_locations/course_location_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_media/course_media_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_repo.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_filter.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_request.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_response.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_search_request.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_search_response.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_translation_request.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_translation_response.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan.dart';
import 'package:fluffychat/pangea/payload_client/payload_client.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CoursePlansRepo {
  static final Map<String, Completer<CoursePlanResponse>> cache = {};
  static final GetStorage _courseStorage = GetStorage("course_storage");
  static const Duration cacheDuration = Duration(days: 1);

  static DateTime? get lastUpdated {
    final entry = _courseStorage.read("last_updated");
    if (entry != null && entry is String) {
      try {
        return DateTime.parse(entry);
      } catch (e) {
        _courseStorage.remove("last_updated");
      }
    }
    return null;
  }

  static Future<CoursePlanResponse> get(
    CoursePlanRequest request,
  ) async {
    await _courseStorage.initStorage;
    final cached = _getCached(request);
    if (cached != null) {
      return cached;
    }

    if (cache.containsKey(request.uuid)) {
      return cache[request.uuid]!.future;
    }

    final completer = Completer<CoursePlanResponse>();
    cache[request.uuid] = completer;

    try {
      final PayloadClient payload = PayloadClient(
        baseUrl: Environment.cmsApi,
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );
      final cmsCoursePlan = await payload.findById(
        "course-plans",
        request.uuid,
        CmsCoursePlan.fromJson,
      );

      final coursePlan = CoursePlanResponse.fromCmsResponse(cmsCoursePlan);
      await _setCached(coursePlan);
      await coursePlan.course.init();
      completer.complete(coursePlan);
      return coursePlan;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      cache.remove(request.uuid);
    }
  }

  static Future<CoursePlanModel> translate(
    TranslateCoursePlanRequest request,
  ) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.coursePlanTranslate,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to translate course plan: ${res.statusCode} ${res.body}",
      );
    }

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));

    final response = TranslateCoursePlanResponse.fromJson(decodedBody);

    return response.coursePlan;
  }

  static Future<CoursePlanSearchResponse> search(
    CoursePlanSearchRequest request,
  ) async {
    final PayloadClient payload = PayloadClient(
      baseUrl: Environment.cmsApi,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final missingIds = request.uuids
        .where(
          (id) => _courseStorage.read(id) == null,
        )
        .toList();

    if (missingIds.isNotEmpty) {
      final searchResult = await payload.find(
        CmsCoursePlan.slug,
        CmsCoursePlan.fromJson,
        page: 1,
        limit: 10,
        where: {
          "id": {"in": missingIds},
        },
      );

      final response = CoursePlanSearchResponse.fromCmsResponse(searchResult);
      await _setCachedBatch(response);

      final futures = response.courses.map((c) => c.init());
      await Future.wait(futures);
    }

    final courses = request.uuids
        .map(
          (id) => _getCached(
            CoursePlanRequest(uuid: id),
          ),
        )
        .whereType<CoursePlanResponse>()
        .toList();

    return CoursePlanSearchResponse(
      courses: courses.map((c) => c.course).toList(),
    );
  }

  static Future<CoursePlanSearchResponse> searchByFilter({
    required CourseFilter filter,
  }) async {
    await _courseStorage.initStorage;

    final PayloadClient payload = PayloadClient(
      baseUrl: Environment.cmsApi,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    // Run the search for the given filter, selecting only the course IDs
    final result = await payload.find(
      CmsCoursePlan.slug,
      (json) => json["id"] as String,
      page: 1,
      limit: 10,
      where: filter.whereFilter,
      select: {"id": true},
    );

    return search(
      CoursePlanSearchRequest(uuids: result.docs),
    );
  }

  static CoursePlanResponse? _getCached(
    CoursePlanRequest request,
  ) {
    if (lastUpdated != null &&
        DateTime.now().difference(lastUpdated!) > cacheDuration) {
      clearCache();
      return null;
    }

    final json = _courseStorage.read(request.uuid);
    if (json != null) {
      try {
        return CoursePlanResponse(
          course: CoursePlanModel.fromJson(json),
        );
      } catch (e) {
        _courseStorage.remove(request.uuid);
      }
    }
    return null;
  }

  static Future<void> _setCached(CoursePlanResponse response) async {
    if (lastUpdated == null) {
      await _courseStorage.write(
        "last_updated",
        DateTime.now().toIso8601String(),
      );
    }

    await _courseStorage.write(
      response.course.uuid,
      response.course.toJson(),
    );
  }

  static Future<void> _setCachedBatch(
    CoursePlanSearchResponse response,
  ) async {
    if (lastUpdated == null) {
      await _courseStorage.write(
        "last_updated",
        DateTime.now().toIso8601String(),
      );
    }

    final List<Future> futures = response.courses.map((course) {
      return _courseStorage.write(
        course.uuid,
        course.toJson(),
      );
    }).toList();

    await Future.wait(futures);
  }

  static Future<void> clearCache() async {
    final List<Future> futures = [
      CourseActivityRepo.clearCache(),
      CourseLocationMediaRepo.clearCache(),
      CourseLocationRepo.clearCache(),
      CourseMediaRepo.clearCache(),
      CourseTopicRepo.clearCache(),
      _courseStorage.erase(),
    ];

    await Future.wait(futures);
  }
}
