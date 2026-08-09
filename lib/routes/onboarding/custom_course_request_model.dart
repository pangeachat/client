import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

class CustomCourseRequestModel {
  final String name;
  final String languagePair;
  final LanguageLevelTypeEnum languageLevel;
  final String institution;
  final String goals;
  final String? notes;
  final bool? mock;

  const CustomCourseRequestModel({
    required this.name,
    required this.languagePair,
    required this.languageLevel,
    required this.institution,
    required this.goals,
    this.mock,
    this.notes,
  });

  String get storageKey =>
      "course-request-$name-$languagePair-${languageLevel.name}-$institution-$goals-$notes";

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
