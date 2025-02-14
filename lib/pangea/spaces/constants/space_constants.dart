import 'package:get_storage/get_storage.dart';

class SpaceConstants {
  static const powerLevelOfAdmin = 100;
  static const languageToolPermissions = 1;
  static const defaultDominantLanguage = "en";
  static const defaultTargetLanguage = "es";
  static const String classCode = 'classcode';
}

class Storage {
  static final GetStorage chatBox = GetStorage("chat_list_storage");
  static final GetStorage classStorage = GetStorage('class_storage');
  static final GetStorage loginBox = GetStorage("login_storage");
  static final GetStorage modeListStorage = GetStorage('mode_list_storage');
  static final GetStorage activityPlanStorage = GetStorage('activity_plan_storage');
  static final GetStorage bookStorage = GetStorage('bookmarked_activities');
  static final GetStorage objectiveListStorage = GetStorage('objective_list_storage');
  static final GetStorage ssoBox = GetStorage("sso_storage");
  static final GetStorage topicListStorage = GetStorage('topic_list_storage');
  static final GetStorage versionBox = GetStorage("version_storage");
  static final GetStorage svgStorage = GetStorage('svg_cache');
  static final GetStorage lemmaStorage = GetStorage('lemma_storage');
  static final GetStorage morphsStorage = GetStorage('morphs_storage');
  static final GetStorage morphMeaningStorage = GetStorage('morph_meaning_storage');
  static final GetStorage linkBox = GetStorage("link_storage");
  static final GetStorage subscriptionBox = GetStorage("subscription_storage");
}
