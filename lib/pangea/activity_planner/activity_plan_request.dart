import 'package:fluffychat/pangea/activity_generator/media_enum.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';

class ActivityPlanRequest {
  final String topic;
  final String mode;
  final String objective;
  final String location;
  final MediaEnum media;
  LanguageLevelTypeEnum cefrLevel;
  final String languageOfInstructions;
  final String targetLanguage;
  final int count;
  int numberOfParticipants;

  ActivityPlanRequest({
    required this.topic,
    required this.mode,
    required this.objective,
    required this.media,
    required this.cefrLevel,
    required this.languageOfInstructions,
    required this.targetLanguage,
    this.location = "any",
    this.count = 3,
    required this.numberOfParticipants,
  });

  /// Fallback for corrupt/incomplete state events where the request is missing.
  factory ActivityPlanRequest.empty() => ActivityPlanRequest(
    topic: '',
    mode: '',
    objective: '',
    media: MediaEnum.nan,
    cefrLevel: LanguageLevelTypeEnum.a1,
    languageOfInstructions: '',
    targetLanguage: '',
    numberOfParticipants: 2,
  );

  Map<String, dynamic> toJson() {
    return {
      ModelKey.activityRequestTopic: topic,
      ModelKey.mode: mode,
      ModelKey.activityRequestObjective: objective,
      ModelKey.activityRequestMedia: media.string,
      ModelKey.activityRequestCefrLevel: cefrLevel.string,
      ModelKey.activityRequestLanguageOfInstructions: languageOfInstructions,
      ModelKey.targetLanguage: targetLanguage,
      ModelKey.activityRequestCount: count,
      ModelKey.activityRequestNumberOfParticipants: numberOfParticipants,
      ModelKey.activityPlanLocation: location,
    };
  }

  factory ActivityPlanRequest.fromJson(Map<String, dynamic> json) => ActivityPlanRequest(
    topic: json[ModelKey.activityRequestTopic] as String? ?? '',
    mode: json[ModelKey.mode] as String? ?? '',
    objective: json[ModelKey.activityRequestObjective] as String? ?? '',
    media: MediaEnum.nan.fromString(json[ModelKey.activityRequestMedia] as String? ?? ''),
    cefrLevel: json[ModelKey.activityRequestCefrLevel] != null
        ? LanguageLevelTypeEnum.fromString(json[ModelKey.activityRequestCefrLevel])
        : LanguageLevelTypeEnum.a1,
    languageOfInstructions: json[ModelKey.activityRequestLanguageOfInstructions] as String? ?? '',
    targetLanguage: json[ModelKey.targetLanguage] as String? ?? '',
    count: json[ModelKey.activityRequestCount] as int? ?? 3,
    numberOfParticipants: json[ModelKey.activityRequestNumberOfParticipants] as int? ?? 2,
    location: json[ModelKey.activityPlanLocation] as String? ?? "any",
  );

  String get storageKey =>
      '$topic-$mode-$objective-${media.string}-$cefrLevel-$languageOfInstructions-$targetLanguage-$numberOfParticipants';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ActivityPlanRequest &&
        other.topic == topic &&
        other.mode == mode &&
        other.objective == objective &&
        other.media == media &&
        other.cefrLevel == cefrLevel &&
        other.languageOfInstructions == languageOfInstructions &&
        other.targetLanguage == targetLanguage &&
        other.location == location &&
        other.count == count &&
        other.numberOfParticipants == numberOfParticipants;
  }

  @override
  int get hashCode =>
      topic.hashCode ^
      mode.hashCode ^
      objective.hashCode ^
      media.hashCode ^
      cefrLevel.hashCode ^
      languageOfInstructions.hashCode ^
      targetLanguage.hashCode ^
      count.hashCode ^
      location.hashCode ^
      numberOfParticipants.hashCode;
}
