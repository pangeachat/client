import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/pangea/common/network/media_url.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';

class ActivityPlanModel {
  final String activityId;

  final ActivityPlanRequest req;
  final String title;
  final String description;
  final String learningObjective;
  final String instructions;
  final List<Vocab> vocab;
  final String? _imageURL;

  /// Ordered stimulus media (carousel) — the v2/v3 model. A single image is a
  /// list of length one; empty means no media (→ placeholder). Upload-kind
  /// blocks must be resolved (`ActivityMediaRepo`) before their URLs render.
  /// The legacy `image_url` single-image path leaves this empty and populates
  /// [_imageURL] instead.
  final List<ActivityMediaBlock> media;

  final DateTime? endAt;
  final Duration? duration;
  final Map<String, ActivityRole>? _roles;
  final bool isDeprecatedModel;

  ActivityPlanModel({
    required this.req,
    required this.title,
    // TODO: when we bring back user's being able to make their own activity,
    // then this should be required
    String? description,
    required this.learningObjective,
    required this.instructions,
    required this.vocab,
    required this.activityId,
    Map<String, ActivityRole>? roles,
    String? imageURL,
    this.media = const [],
    this.endAt,
    this.duration,
    this.isDeprecatedModel = false,
  }) : description = (description == null || description.isEmpty)
           ? learningObjective
           : description,
       _roles = roles,
       _imageURL = imageURL;

  /// This plan with its media list replaced (used after `ActivityMediaRepo`
  /// resolution attaches CDN URLs to the blocks).
  ActivityPlanModel withMedia(List<ActivityMediaBlock> media) =>
      ActivityPlanModel(
        req: req,
        title: title,
        description: description,
        learningObjective: learningObjective,
        instructions: instructions,
        vocab: vocab,
        activityId: activityId,
        roles: _roles,
        imageURL: _imageURL,
        media: media,
        endAt: endAt,
        duration: duration,
        isDeprecatedModel: isDeprecatedModel,
      );

  List<String> get placeholderImages => [
    "${AppConfig.assetsBaseURL}/Space%20template%202.png",
    "${AppConfig.assetsBaseURL}/Space%20template%203.png",
    "${AppConfig.assetsBaseURL}/Space%20template%204.png",
  ];

  String get randomPlaceholder =>
      placeholderImages[Random(
        title.hashCode,
      ).nextInt(placeholderImages.length)];

  /// First image block in the media carousel, if any (the "hero").
  ActivityMediaBlock? get heroImage =>
      media.firstWhereOrNull((b) => b.isImage);

  /// First media block of any kind — the compact-surface "hero". Cards, list
  /// tiles, and map pins show this block standing in for the whole carousel,
  /// with a play badge when it is a video. Contrast [heroImage], which skips to
  /// the first *image* (used by the single-image paths: chat background, room
  /// avatar).
  ActivityMediaBlock? get heroBlock => media.firstOrNull;

  /// Whether the activity has any video or YouTube block — media that plays.
  /// The live session shows the inline carousel (so it can be played) only for
  /// these, and suppresses the blurred background image in that case;
  /// image-only activities keep the background. See activities.instructions.md.
  bool get hasPlayableMedia => media.any((b) => b.isVideo || b.isYoutube);

  /// The hero image to render today (the carousel is a follow-up). Resolution
  /// order: the first resolved image block in the v2/v3 `media` list → the
  /// legacy single `image_url` (the choreo `/activity_plan/localize` path) →
  /// a deterministic placeholder when the activity genuinely has no image.
  ///
  /// image-cdn cutover: both the resolved media URL and the legacy `image_url`
  /// are absolute CDN urls used as-is; `resolveMediaUrl` prepends the CMS origin
  /// only for legacy relative paths. See media_url.dart and
  /// `.github/.github/instructions/activities.instructions.md`.
  Uri? get imageURL {
    final heroUrl = heroImage?.displayUrl();
    if (heroUrl != null) return Uri.tryParse(heroUrl);
    return resolveMediaUrl(_imageURL) ?? Uri.tryParse(randomPlaceholder);
  }

  Map<String, ActivityRole> get roles {
    if (_roles != null) return _roles;
    final defaultRoles = <String, ActivityRole>{};
    for (int i = 0; i < req.numberOfParticipants; i++) {
      defaultRoles['role_$i'] = ActivityRole(
        id: 'role_$i',
        name: 'Participant',
        goal: learningObjective,
        goals: [],
        avatarUrl: null,
      );
    }
    return defaultRoles;
  }

  factory ActivityPlanModel.fromJson(Map<String, dynamic> json) {
    final req = ActivityPlanRequest.fromJson(
      json[ActivitySessionConstants.activityPlanRequest],
    );

    Map<String, ActivityRole>? roles;
    final roleContent = json['roles'];
    if (roleContent is Map<String, dynamic>) {
      roles = Map<String, ActivityRole>.from(
        json['roles'].map(
          (key, value) => MapEntry(key, ActivityRole.fromJson(value)),
        ),
      );
    }

    final activityId =
        json[ActivitySessionConstants.activityId] ?? json["bookmark_id"];
    if (activityId == null) {
      throw ArgumentError('Activity ID is required');
    }

    return ActivityPlanModel(
      imageURL: json[ActivitySessionConstants.activityPlanImageURL],
      media:
          (json[ActivitySessionConstants.activityPlanMedia] as List?)
              ?.whereType<Map>()
              .map(
                (e) =>
                    ActivityMediaBlock.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const [],
      instructions: json[ActivitySessionConstants.activityPlanInstructions],
      req: req,
      title: json[ActivitySessionConstants.activityPlanTitle],
      description:
          json[ActivitySessionConstants.description] ??
          json[ActivitySessionConstants.activityPlanLearningObjective],
      learningObjective:
          json[ActivitySessionConstants.activityPlanLearningObjective],
      vocab: List<Vocab>.from(
        json[ActivitySessionConstants.activityPlanVocab].map(
          (vocab) => Vocab.fromJson(vocab),
        ),
      ),
      endAt: json[ActivitySessionConstants.activityPlanEndAt] != null
          ? DateTime.parse(json[ActivitySessionConstants.activityPlanEndAt])
          : null,
      duration: json[ActivitySessionConstants.duration] != null
          ? Duration(
              days: json[ActivitySessionConstants.duration]['days'] ?? 0,
              hours: json[ActivitySessionConstants.duration]['hours'] ?? 0,
              minutes: json[ActivitySessionConstants.duration]['minutes'] ?? 0,
            )
          : null,
      roles: roles,
      activityId: activityId,
      isDeprecatedModel: json["bookmark_id"] != null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ActivitySessionConstants.activityId: activityId,
      ActivitySessionConstants.activityPlanImageURL: _imageURL,
      ActivitySessionConstants.activityPlanMedia: media
          .map((block) => block.toJson())
          .toList(),
      ActivitySessionConstants.activityPlanInstructions: instructions,
      ActivitySessionConstants.activityPlanRequest: req.toJson(),
      ActivitySessionConstants.activityPlanTitle: title,
      ActivitySessionConstants.description: description,
      ActivitySessionConstants.activityPlanLearningObjective: learningObjective,
      ActivitySessionConstants.activityPlanVocab: vocab
          .map((vocab) => vocab.toJson())
          .toList(),
      ActivitySessionConstants.activityPlanEndAt: endAt?.toIso8601String(),
      ActivitySessionConstants.duration: {
        'days': duration?.inDays ?? 0,
        'hours': duration?.inHours.remainder(24) ?? 0,
        'minutes': duration?.inMinutes.remainder(60) ?? 0,
      },
      'roles': _roles?.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  String get vocabString {
    final List<String> vocabList = [];
    String vocabString = "";
    // cycle through vocab with index
    for (var i = 0; i < vocab.length; i++) {
      // if the lemma appears more than once in the vocab list, show the pos
      // vocab is a wrapped list of string, separated by commas
      final v = vocab[i];
      final bool showPos =
          vocab.where((vocab) => vocab.lemma == v.lemma).length > 1;
      vocabString +=
          '${v.lemma}${showPos ? ' (${v.pos})' : ''}${i + 1 < vocab.length ? ', ' : ''}';
      vocabList.add("${v.lemma}${showPos ? ' (${v.pos})' : ''}");
    }
    return vocabString;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ActivityPlanModel &&
        other.req == req &&
        other.title == title &&
        other.learningObjective == learningObjective &&
        other.instructions == instructions &&
        other.description == description &&
        listEquals(other.vocab, vocab) &&
        other._imageURL == _imageURL;
  }

  @override
  int get hashCode =>
      req.hashCode ^
      title.hashCode ^
      learningObjective.hashCode ^
      description.hashCode ^
      instructions.hashCode ^
      Object.hashAll(vocab) ^
      _imageURL.hashCode;
}

class Vocab {
  final String lemma;
  final String pos;

  Vocab({required this.lemma, required this.pos});

  factory Vocab.fromJson(Map<String, dynamic> json) {
    return Vocab(lemma: json[ModelKey.lemma], pos: json['pos']);
  }

  PangeaToken asToken() {
    final text = PangeaTokenText(
      content: lemma,
      length: lemma.characters.length,
      offset: 0,
    );

    return PangeaToken(
      text: text,
      lemma: Lemma(text: lemma, saveVocab: true, form: lemma),
      pos: pos,
      morph: {},
    );
  }

  Map<String, dynamic> toJson() {
    return {ModelKey.lemma: lemma, 'pos': pos};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Vocab && other.lemma == lemma && other.pos == pos;
  }

  @override
  int get hashCode => lemma.hashCode ^ pos.hashCode;
}

class ActivityRole {
  final String id;
  final String name;
  final String? goal;
  final List<ActivityRoleGoal> goals;
  final String? avatarUrl;

  ActivityRole({
    required this.id,
    required this.name,
    required this.goal,
    required this.goals,
    this.avatarUrl,
  });

  String get _defaultGoalId => "$id:legacy";

  List<ActivityRoleGoal> get allGoals {
    if (goals.isNotEmpty) return goals;
    final goal = this.goal;
    if (goal == null) return [];
    return [ActivityRoleGoal(id: _defaultGoalId, description: goal)];
  }

  factory ActivityRole.fromJson(Map<String, dynamic> json) {
    final urlContent = json['avatar_url'] as String?;
    String? avatarUrl;
    if (urlContent != null && urlContent.isNotEmpty) {
      avatarUrl = urlContent;
    }

    return ActivityRole(
      id: json['id'] as String,
      name: json['name'] as String,
      goal: json['goal'] as String?,
      goals: json["goals"] != null
          ? List.from(json["goals"])
                .map(
                  (e) =>
                      ActivityRoleGoal.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : [],
      avatarUrl: avatarUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'goal': goal,
      'avatar_url': avatarUrl,
      "goals": goals.map((g) => g.toJson()).toList(),
    };
  }
}

class ActivityRoleGoal {
  final String id;
  final String description;

  const ActivityRoleGoal({required this.id, required this.description});

  Map<String, dynamic> toJson() => {"id": id, "description": description};

  factory ActivityRoleGoal.fromJson(Map<String, dynamic> json) =>
      ActivityRoleGoal(id: json["id"], description: json["description"]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityRoleGoal &&
          id == other.id &&
          description == other.description;

  @override
  int get hashCode => id.hashCode ^ description.hashCode;
}
