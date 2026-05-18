import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/account_updater.dart';
import 'package:fluffychat/pangea/onboarding/avatar_provider.dart';
import 'package:fluffychat/pangea/onboarding/course_provider.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';

class OnboardingStateController {
  final AccountUpdater accountUpdater;
  final CourseProvider courseProvider;
  final AvatarProvider avatarProvider;

  OnboardingStateController({
    required this.accountUpdater,
    required this.courseProvider,
    required this.avatarProvider,
  });

  UserType? _userType;

  LanguageModel? _baseLanguage;
  LanguageModel? _targetLanguage;
  LanguageLevelTypeEnum? _languageLevel;

  String? _courseCode;
  CoursePlanModel? _joinedCoursePlan;
  String? _joinedRoomId;

  UserType? get userType => _userType;

  LanguageModel? get baseLanguage => _baseLanguage;
  LanguageModel? get targetLanguage => _targetLanguage;
  LanguageLevelTypeEnum? get languageLevel => _languageLevel;

  String? get courseCode => _courseCode;
  CoursePlanModel? get joinedCoursePlan => _joinedCoursePlan;
  String? get joinedRoomId => _joinedRoomId;

  void setUserType(UserType type) => _userType = type;

  void setBaseLanguage(LanguageModel? lang) => _baseLanguage = lang;
  void setTargetLanguage(LanguageModel? lang) => _targetLanguage = lang;
  void setLanguageLevel(LanguageLevelTypeEnum? level) => _languageLevel = level;

  void setCourseCode(String courseCode) => _courseCode = courseCode;
  void setJoinedCoursePlan(CoursePlanModel coursePlan) =>
      _joinedCoursePlan = coursePlan;
  void setJoinedRoomId(String roomId) => _joinedRoomId = roomId;
}
