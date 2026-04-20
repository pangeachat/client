import 'package:fluffychat/pangea/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/pangea/chat_settings/constants/bot_constants.dart';
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

  Map<String, dynamic> toJson() {
    return {
      ActivitySessionConstants.activityRequestTopic: topic,
      BotConstants.mode: mode,
      ActivitySessionConstants.activityRequestObjective: objective,
      ActivitySessionConstants.activityRequestMedia: media.string,
      ActivitySessionConstants.activityRequestCefrLevel: cefrLevel.string,
      ActivitySessionConstants.activityRequestLanguageOfInstructions:
          languageOfInstructions,
      ModelKey.targetLanguage: targetLanguage,
      ActivitySessionConstants.activityRequestCount: count,
      ActivitySessionConstants.activityRequestNumberOfParticipants:
          numberOfParticipants,
      ActivitySessionConstants.activityPlanLocation: location,
    };
  }

  factory ActivityPlanRequest.fromJson(
    Map<String, dynamic> json,
  ) => ActivityPlanRequest(
    topic: json[ActivitySessionConstants.activityRequestTopic],
    mode: json[BotConstants.mode],
    objective: json[ActivitySessionConstants.activityRequestObjective],
    media: MediaEnum.nan.fromString(
      json[ActivitySessionConstants.activityRequestMedia],
    ),
    cefrLevel: json[ActivitySessionConstants.activityRequestCefrLevel] != null
        ? LanguageLevelTypeEnum.fromString(
            json[ActivitySessionConstants.activityRequestCefrLevel],
          )
        : LanguageLevelTypeEnum.a1,
    languageOfInstructions:
        json[ActivitySessionConstants.activityRequestLanguageOfInstructions],
    targetLanguage: json[ModelKey.targetLanguage],
    count: json[ActivitySessionConstants.activityRequestCount],
    numberOfParticipants:
        json[ActivitySessionConstants.activityRequestNumberOfParticipants],
    location: json[ActivitySessionConstants.activityPlanLocation] ?? "any",
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
