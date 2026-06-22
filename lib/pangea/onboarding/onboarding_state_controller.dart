import 'dart:typed_data';

import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/account_updater.dart';
import 'package:fluffychat/pangea/onboarding/avatar_provider.dart';
import 'package:fluffychat/pangea/onboarding/course_provider.dart';
import 'package:fluffychat/pangea/onboarding/trial_info_provider.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';

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
  });

  AvatarInfo? _avatarInfo;
  String? _displayName;

  UserType? _userType;

  LanguageModel? _baseLanguage;
  LanguageModel? _targetLanguage;
  LanguageLevelTypeEnum? _languageLevel;

  String? _courseCode;
  CoursePlanModel? _joinedCoursePlan;
  String? _joinedRoomId;

  AvatarInfo? get avatarInfo => _avatarInfo;
  String? get displayName => _displayName;

  UserType? get userType => _userType;

  LanguageModel? get baseLanguage => _baseLanguage;
  LanguageModel? get targetLanguage => _targetLanguage;
  LanguageLevelTypeEnum? get languageLevel => _languageLevel;

  String? get courseCode => _courseCode;
  CoursePlanModel? get joinedCoursePlan => _joinedCoursePlan;
  String? get joinedRoomId => _joinedRoomId;

  void setAvatarInfo(AvatarInfo info) => _avatarInfo = info;
  void setDisplayName(String displayName) => _displayName = displayName;

  void setUserType(UserType type) => _userType = type;

  void setBaseLanguage(LanguageModel? lang) => _baseLanguage = lang;
  void setTargetLanguage(LanguageModel? lang) => _targetLanguage = lang;
  void setLanguageLevel(LanguageLevelTypeEnum? level) => _languageLevel = level;

  void setCourseCode(String courseCode) => _courseCode = courseCode;
  void setJoinedCoursePlan(CoursePlanModel coursePlan) =>
      _joinedCoursePlan = coursePlan;
  void setJoinedRoomId(String roomId) => _joinedRoomId = roomId;
}
