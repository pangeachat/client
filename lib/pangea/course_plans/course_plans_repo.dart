import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/course_plans/cms_course_plan.dart';
import 'package:fluffychat/pangea/course_plans/course_plan_model.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/payload_client/payload_client.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:get_storage/get_storage.dart';

class CourseFilter {
  final LanguageModel? targetLanguage;
  final LanguageModel? languageOfInstructions;
  final LanguageLevelTypeEnum? cefrLevel;

  CourseFilter({
    this.targetLanguage,
    this.languageOfInstructions,
    this.cefrLevel,
  });
}

class CoursePlansRepo {
  static final GetStorage _courseStorage = GetStorage("course_storage");

  static final PayloadClient payload = PayloadClient(
    baseUrl: Environment.cmsApi,
    accessToken: MatrixState.pangeaController.userController.accessToken,
  );

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

  static List<CoursePlanModel> _getAllCached() {
    final keys = _courseStorage.getKeys();
    return keys
        .map((key) => _getCached(key))
        .whereType<CoursePlanModel>()
        .toList();
  }

  static Future<void> set(CoursePlanModel coursePlan) async {
    await _courseStorage.write(coursePlan.uuid, coursePlan.toJson());
  }

  static Future<CoursePlanModel?> get(String id) async {
    final cached = _getCached(id);
    if (cached != null) {
      return cached;
    }
    final result =
        await payload.findById("course-plans", id, CmsCoursePlan.fromJson);

    final coursePlan = await CoursePlanModel.fromCmsCoursePlan(result, payload);

    await set(coursePlan);

    return coursePlan;
  }

  static Future<List<CoursePlanModel>> search({CourseFilter? filter}) async {
    final cached = _getAllCached();
    if (cached.isNotEmpty) {
      return cached.filtered(filter);
    }
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
            "cefrLevel": {"equals": filter.cefrLevel},
          });
        }
        if (filter.languageOfInstructions != null) {
          where["and"].add({
            "languageOfInstructions": {"equals": filter.languageOfInstructions},
          });
        }
        if (filter.targetLanguage != null) {
          where["and"].add({
            "targetLanguage": {"equals": filter.targetLanguage},
          });
        }
      } else if (numberOfFilter == 1) {
        if (filter.cefrLevel != null) {
          where["cefrLevel"] = {"equals": filter.cefrLevel};
        }
        if (filter.languageOfInstructions != null) {
          where["languageOfInstructions"] = {
            "equals": filter.languageOfInstructions,
          };
        }
        if (filter.targetLanguage != null) {
          where["targetLanguage"] = {"equals": filter.targetLanguage};
        }
      }
    }

    final result = await payload.find(
      "course-plans",
      CmsCoursePlan.fromJson,
      page: 1,
      limit: 10,
      where: where,
    );

    final coursePlans = await Future.wait(
      result.docs.map((resp) async {
        final coursePlan =
            await CoursePlanModel.fromCmsCoursePlan(resp, payload);
        await set(coursePlan);
        return coursePlan;
      }),
    );

    for (final plan in coursePlans) {
      set(plan);
    }

    return coursePlans;
  }
}

extension on List<CoursePlanModel> {
  List<CoursePlanModel> filtered(CourseFilter? filter) {
    return where((course) {
      final matchesTargetLanguage = filter?.targetLanguage == null ||
          course.targetLanguage.split("-").first ==
              filter?.targetLanguage?.langCodeShort;

      final matchesLanguageOfInstructions =
          filter?.languageOfInstructions == null ||
              course.languageOfInstructions.split("-").first ==
                  filter?.languageOfInstructions?.langCodeShort;

      final matchesCefrLevel =
          filter?.cefrLevel == null || course.cefrLevel == filter?.cefrLevel;

      return matchesTargetLanguage &&
          matchesLanguageOfInstructions &&
          matchesCefrLevel;
    }).toList();
  }
}
