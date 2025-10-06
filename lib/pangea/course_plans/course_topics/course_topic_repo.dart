import 'dart:async';
import 'dart:convert';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/course_plans/course_info_batch_request.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_model.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_response.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_translation_request.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_translation_response.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan_topic.dart';
import 'package:fluffychat/pangea/payload_client/payload_client.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseTopicRepo {
  static final Map<String, Completer<CourseTopicResponse>> _cache = {};
  static final GetStorage _storage = GetStorage('course_topic_storage');

  static Future<CourseTopicResponse> get(
    CourseInfoBatchRequest request,
  ) async {
    final topics = <CourseTopicModel>[];

    await _storage.initStorage;
    topics.addAll(getCached(request).topics);

    final toFetch = request.uuids
        .where((uuid) => topics.indexWhere((topic) => topic.uuid == uuid) == -1)
        .toList();

    if (toFetch.isNotEmpty) {
      final fetchedTopics = await _fetch(
        CourseInfoBatchRequest(
          batchId: request.batchId,
          uuids: toFetch,
        ),
      );
      topics.addAll(fetchedTopics.topics);
      await _setCached(fetchedTopics);
    }

    return CourseTopicResponse(topics: topics);
  }

  static Future<CourseTopicModel> translate(
    TranslateTopicRequest request,
  ) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.coursePlanTopicTranslate,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to translate topic. Status code: ${res.statusCode}",
      );
    }

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));

    final response = TranslateTopicResponse.fromJson(decodedBody);

    return response.topic;
  }

  static Future<CourseTopicResponse> _fetch(
    CourseInfoBatchRequest request,
  ) async {
    if (_cache.containsKey(request.batchId)) {
      return _cache[request.batchId]!.future;
    }

    final completer = Completer<CourseTopicResponse>();
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
      final cmsCourseTopicsResult = await payload.find(
        CmsCoursePlanTopic.slug,
        CmsCoursePlanTopic.fromJson,
        where: where,
        limit: limit,
        page: 1,
        sort: "createdAt",
      );

      final response = CourseTopicResponse.fromCmsResponse(
        cmsCourseTopicsResult,
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

  static CourseTopicResponse getCached(CourseInfoBatchRequest request) {
    final List<CourseTopicModel> topics = [];
    for (final uuid in request.uuids) {
      final json = _storage.read(uuid);
      if (json != null) {
        try {
          final topic = CourseTopicModel.fromJson(
            Map<String, dynamic>.from(json),
          );
          topics.add(topic);
        } catch (e) {
          _storage.remove(uuid);
        }
      }
    }

    return CourseTopicResponse(topics: topics);
  }

  static Future<void> _setCached(CourseTopicResponse response) async {
    final List<Future> futures = [];
    for (final topic in response.topics) {
      futures.add(_storage.write(topic.uuid, topic.toJson()));
    }
    await Future.wait(futures);
  }

  static Future<void> clearCache() async {
    await _storage.erase();
  }
}
