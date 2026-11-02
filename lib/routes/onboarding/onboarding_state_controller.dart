import 'dart:typed_data';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

class AvatarInfo {
  final Uri? avatarUrl;
  final Uint8List? avatarBytes;

  const AvatarInfo({this.avatarUrl, this.avatarBytes});
}

class OnboardingStateController {
  final AccountUpdater accountUpdater;
  final CourseProvider courseProvider;
  final AvatarProvider avatarProvider;
  final TrialInfoProvider trialInfoProvider;

  OnboardingStateController({
    required this.accountUpdater,
    required this.courseProvider,
    required this.avatarProvider,
    required this.trialInfoProvider,
    UserType? userType,
  }) : _userType = userType;

  AvatarInfo? _avatarInfo;
  String? _displayName;

  UserType? _userType;

  LanguageModel? _baseLanguage;
  LanguageModel? _targetLanguage;
  LanguageLevelTypeEnum? _languageLevel;

  String? _courseCode;
  String? _joinedCode;
  String? _linkJoinedRoomId;
  CoursePlanModel? _joinedCoursePlan;
  String? _joinedRoomId;

  String? _courseRequestName;
  String? _courseRequestInstitution;
  String? _courseRequestGoals;
  String? _sentCourseRequestKey;

  AvatarInfo? get avatarInfo => _avatarInfo;
  String? get displayName => _displayName;

  UserType? get userType => _userType;

  LanguageModel? get baseLanguage => _baseLanguage;
  LanguageModel? get targetLanguage => _targetLanguage;
  LanguageLevelTypeEnum? get languageLevel => _languageLevel;

  String? get courseCode => _courseCode;

  /// The class code the person last joined a course with, so moving forward
  /// again over the class-code page with the same code doesn't join again.
  String? get joinedCode => _joinedCode;

  /// The course joined from a class link. The link's code is used up by the
  /// join, so going back to the role page and forward again continues from
  /// this course rather than asking for a code.
  String? get linkJoinedRoomId => _linkJoinedRoomId;

  CoursePlanModel? get joinedCoursePlan => _joinedCoursePlan;
  String? get joinedRoomId => _joinedRoomId;

  String? get courseRequestName => _courseRequestName;
  String? get courseRequestInstitution => _courseRequestInstitution;
  String? get courseRequestGoals => _courseRequestGoals;

  /// The course request already sent in this run, so moving forward again
  /// with nothing changed doesn't send a second one.
  String? get sentCourseRequestKey => _sentCourseRequestKey;

  void setAvatarInfo(AvatarInfo info) => _avatarInfo = info;
  void setDisplayName(String displayName) => _displayName = displayName;

  /// Switching role keeps the level, like every other choice; the level page
  /// shows whatever is in memory selected.
  void setUserType(UserType type) => _userType = type;

  void setBaseLanguage(LanguageModel? lang) => _baseLanguage = lang;
  void setTargetLanguage(LanguageModel? lang) => _targetLanguage = lang;
  void setLanguageLevel(LanguageLevelTypeEnum? level) => _languageLevel = level;

  void setCourseCode(String courseCode) => _courseCode = courseCode;
  void setJoinedCode(String code) => _joinedCode = code;
  void setLinkJoinedRoomId(String roomId) => _linkJoinedRoomId = roomId;
  void setJoinedCoursePlan(CoursePlanModel coursePlan) =>
      _joinedCoursePlan = coursePlan;
  void setJoinedRoomId(String roomId) => _joinedRoomId = roomId;

  void setCourseRequestName(String name) => _courseRequestName = name;
  void setCourseRequestInstitution(String institution) =>
      _courseRequestInstitution = institution;
  void setCourseRequestGoals(String goals) => _courseRequestGoals = goals;
  void setSentCourseRequestKey(String key) => _sentCourseRequestKey = key;
}
