import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

class CustomCourseRequestModel extends BaseRequest {
  final String name;
  final String languagePair;
  final LanguageLevelTypeEnum languageLevel;
  final String institution;
  final String goals;
  final String? notes;
  final bool? mock;

  CustomCourseRequestModel({
    required this.name,
    required this.languagePair,
    required this.languageLevel,
    required this.institution,
    required this.goals,
    this.mock,
    this.notes,
  });

  @override
  String get storageKey =>
      "course-request-$name-$languagePair-${languageLevel.name}-$institution-$goals-$notes";

  @override
  Map<String, dynamic> toJson() => {
    "name": name,
    "language_pair": languagePair,
    "proficiency_level": languageLevel.string,
    "institution": institution,
    "goals": goals,
    "notes": notes,
    if (mock != null) ModelKey.mock: mock,
  };
}
