import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/course_plans/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/course_topic_model.dart';
import 'package:fluffychat/pangea/course_plans/translate_schema.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan.dart';
import 'package:fluffychat/pangea/payload_client/payload_client.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

class CourseFilter {
  final LanguageModel? targetLanguage;
  final LanguageModel? languageOfInstructions;
  final LanguageLevelTypeEnum? cefrLevel;

  CourseFilter({
    this.targetLanguage,
    this.languageOfInstructions,
    this.cefrLevel,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CourseFilter &&
        other.targetLanguage == targetLanguage &&
        other.languageOfInstructions == languageOfInstructions &&
        other.cefrLevel == cefrLevel;
  }

  @override
  int get hashCode =>
      targetLanguage.hashCode ^
      languageOfInstructions.hashCode ^
      cefrLevel.hashCode;
}

class CoursePlansRepo {
  static final Map<String, Completer<CoursePlanModel>> cache = {};
  static final GetStorage _courseStorage = GetStorage("course_storage");

  static CoursePlanModel? _getCached(String id) {
    final json = _courseStorage.read(id);
    if (json != null) {
      try {
        return CoursePlanModel.fromJson(json);
      } catch (e) {
        _courseStorage.remove(id);
      }
    }
    return null;
  }

  static Future<void> _setCached(CoursePlanModel coursePlan) async {
    await _courseStorage.write(coursePlan.uuid, coursePlan.toJson());
  }

  static Future<CoursePlanModel> get(String id) async {
    await _courseStorage.initStorage;
    final cached = _getCached(id);
    if (cached != null) {
      return cached;
    }

    if (cache.containsKey(id)) {
      return cache[id]!.future;
    }

    final completer = Completer<CoursePlanModel>();
    cache[id] = completer;

    try {
      final PayloadClient payload = PayloadClient(
        baseUrl: Environment.cmsApi,
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );
      final cmsCoursePlan = await payload.findById(
        "course-plans",
        id,
        CmsCoursePlan.fromJson,
      );

      final coursePlan = cmsCoursePlan.toCoursePlanModel();
      await _setCached(coursePlan);
      await coursePlan.init();
      completer.complete(coursePlan);
      return coursePlan;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      cache.remove(id);
    }
  }

  static Future<List<CoursePlanModel>> search({CourseFilter? filter}) async {
    await _courseStorage.initStorage;

    final Map<String, dynamic> where = {};
    if (filter != null) {
      int numberOfFilter = 0;
      if (filter.cefrLevel != null) {
        numberOfFilter += 1;
      }
      if (filter.languageOfInstructions != null) {
        numberOfFilter += 1;
      }
      if (filter.targetLanguage != null) {
        numberOfFilter += 1;
      }
      if (numberOfFilter > 1) {
        where["and"] = [];
        if (filter.cefrLevel != null) {
          where["and"].add({
            "cefrLevel": {"equals": filter.cefrLevel!.string},
          });
        }
        if (filter.languageOfInstructions != null) {
          where["and"].add({
            "l1": {
              "equals": filter.languageOfInstructions!.langCodeShort,
            },
          });
        }
        if (filter.targetLanguage != null) {
          where["and"].add({
            "l2": {"equals": filter.targetLanguage!.langCodeShort},
          });
        }
      } else if (numberOfFilter == 1) {
        if (filter.cefrLevel != null) {
          where["cefrLevel"] = {"equals": filter.cefrLevel!.string};
        }
        if (filter.languageOfInstructions != null) {
          where["l1"] = {
            "equals": filter.languageOfInstructions!.langCode,
          };
        }
        if (filter.targetLanguage != null) {
          where["l2"] = {"equals": filter.targetLanguage!.langCode};
        }
      }
    }

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
      where: where,
      select: {"id": true},
    );

    final missingIds = result.docs
        .where(
          (id) => _courseStorage.read(id) == null,
        )
        .toList();

    // If all of the returned IDs are in the cached list,  ensure all of the course details have been cached, and return
    if (missingIds.isEmpty) {
      return result.docs
          .map((id) => _getCached(id))
          .whereType<CoursePlanModel>()
          .toList();
    }

    // Else, take the list of returned course IDs minus the list of cached course IDs and
    // fetch/cache the course details for each. Cache the newly returned list with all the IDs.
    where["id"] = {
      "in": missingIds,
    };

    final searchResult = await payload.find(
      CmsCoursePlan.slug,
      CmsCoursePlan.fromJson,
      page: 1,
      limit: 10,
      where: where,
    );

    final coursePlans = searchResult.docs
        .map(
          (cmsCoursePlan) => cmsCoursePlan.toCoursePlanModel(),
        )
        .toList();

    for (final plan in coursePlans) {
      await _setCached(plan);
    }

    final futures = coursePlans.map((c) => c.init());
    await Future.wait(futures);

    return result.docs
        .map((id) => _getCached(id))
        .whereType<CoursePlanModel>()
        .toList();
  }

  static Future<CoursePlanModel> translateCoursePlan(
    TranslateCoursePlanRequest request,
  ) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    // Call translate endpoint 12 times, each with 5s timeout
    // until we get a 200 or a max of 12 calls - 1 minute
    for (int i = 0; i < 12; i++) {
      final Response res = await req.post(
        url: PApiUrls.coursePlanTranslate,
        body: request.toJson(),
      );

      if (res.statusCode == 200) {
        final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
        final response = TranslateCoursePlanResponse.fromJson(decodedBody);
        if (response.coursePlan != null) {
          return response.coursePlan!;
        }
      } else if (res.statusCode == 202) {
        // Still processing, wait and retry
      } else {
        throw Exception("Failed to translate course plan");
      }

      await Future.delayed(Duration(seconds: i == 0 ? 0 : 5));
    }

    throw Exception("Translation timed out");
  }

  static Future<CourseTopicModel> translateTopic(
    TranslateTopicRequest request,
  ) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    // Call translate endpoint 12 times, each with 5s timeout
    // until we get a 200 or a max of 12 calls - 1 minute
    for (int i = 0; i < 12; i++) {
      final Response res = await req.post(
        url: PApiUrls.coursePlanTopicTranslate,
        body: request.toJson(),
      );

      if (res.statusCode == 200) {
        final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
        final response = TranslateTopicResponse.fromJson(decodedBody);
        if (response.topic != null) {
          return response.topic!;
        }
      } else if (res.statusCode == 202) {
        // Still processing, wait and retry
      } else {
        throw Exception("Failed to translate topic");
      }

      await Future.delayed(Duration(seconds: i == 0 ? 0 : 5));
    }

    throw Exception("Translation timed out");
  }

  static Future<ActivityPlanModel> translateActivity(
    TranslateActivityRequest request,
  ) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    // Call translate endpoint 12 times, each with 5s timeout
    // until we get a 200 or a max of 12 calls - 1 minute
    for (int i = 0; i < 12; i++) {
      final Response res = await req.post(
        url: PApiUrls.coursePlanActivityTranslate,
        body: request.toJson(),
      );

      if (res.statusCode == 200) {
        final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
        final response = TranslateActivityResponse.fromJson(decodedBody);
        if (response.plan != null) {
          return response.plan!;
        }
      } else if (res.statusCode == 202) {
        // Still processing, wait and retry
      } else {
        throw Exception("Failed to translate activity");
      }

      await Future.delayed(Duration(seconds: i == 0 ? 0 : 5));
    }

    throw Exception("Translation timed out");
  }
}
