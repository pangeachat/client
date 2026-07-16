import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/network/media_url.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';

class ActivityPlanModel {
  final String activityId;

  /// The pinned Payload version this plan was read at, when known. Sessions
  /// pin `(activity_id, version_id)` into `pangea.activity_plan` room state at
  /// creation so scoring stays stable against later owner edits; the in-room
  /// read passes it back as `?version=`. Null for legacy embedded rooms and
  /// for card/lobby reads that don't pin. See activities.instructions.md.
  final String? versionId;

  /// Pin-resolution outcome at the time this plan was last read, parallel to
  /// [versionId]. True when the pinned version was evicted and the latest was
  /// served (scoring fails closed); [fallbackCause] says why it degraded. Drive
  /// the `version_pin_honored` analytics dimension off `!usedFallbackVersion`.
  final bool usedFallbackVersion;
  final String? fallbackCause;

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
    this.versionId,
    this.usedFallbackVersion = false,
    this.fallbackCause,
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
        versionId: versionId,
        usedFallbackVersion: usedFallbackVersion,
        fallbackCause: fallbackCause,
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
  ActivityMediaBlock? get heroImage => media.firstWhereOrNull((b) => b.isImage);

  /// First media block of any kind — the compact-surface "hero". Cards, list
  /// tiles, and map pins show this block standing in for the whole carousel,
  /// with a play badge when it is a video. Contrast [heroImage], which skips to
  /// the first *image* (used by the single-image paths: chat background, room
  /// avatar).
  ActivityMediaBlock? get heroBlock => media.firstOrNull;

  /// First *visible* media block (image / video / youtube) — the lead the
  /// focused start-page hero renders. Skips non-visual (audio) blocks so an
  /// audio-first activity doesn't try to paint an audio URL as an image.
  ActivityMediaBlock? get visibleHeroBlock =>
      media.firstWhereOrNull((b) => b.isImage || b.isVideo || b.isYoutube);

  /// The poster the start-page hero shows: the visible lead block's image (a
  /// video/YouTube block resolves to its poster frame, so a video-first
  /// activity leads with its own frame instead of the generic placeholder),
  /// falling back to [imageURL] (legacy single image → deterministic
  /// placeholder) when there is no visible block.
  Uri? get heroDisplayUrl {
    final url = visibleHeroBlock?.displayUrl();
    return url != null ? Uri.tryParse(url) : imageURL;
  }

  /// Whether the start-page hero's lead block plays — a video or YouTube clip.
  /// Drives the hero's play badge and inline player. An image (or no media)
  /// lead is not playable and renders as a still.
  bool get heroIsPlayable {
    final b = visibleHeroBlock;
    return b != null && (b.isVideo || b.isYoutube);
  }

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

  /// Roles come from the CMS activity, the single source of truth for role ids.
  /// We never mint placeholder roles: a minted `role_$i` id diverges from the
  /// CMS role id the bot/orchestrator use, so the learner's pick silently fails
  /// to match and no goals are ever awarded. A plan with no roles is a bug that
  /// must surface (the parse sites log it loudly) — return empty, not fakes.
  Map<String, ActivityRole> get roles => _roles ?? const {};

  /// The stars ONE player can earn in this activity: their role's goal count.
  /// Generation guarantees the count is uniform across roles; plans predating
  /// that rule may differ, so this takes the min across roles — permissive
  /// (org activities doc, goal-progression invariants). The single home for
  /// the rule: card star rows, the map's large card, and the Mission threshold
  /// ceiling (quest_progression_resolver.dart) all read this. 0 when the plan
  /// has no roles (degraded data — surfaces elsewhere).
  int get earnableStars {
    if (roles.isEmpty) return 0;
    return roles.values
        .map((r) => r.allGoals.length)
        .reduce((a, b) => b < a ? b : a);
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
      versionId: json[ActivitySessionConstants.versionId] as String?,
      usedFallbackVersion:
          json[ActivitySessionConstants.usedFallbackVersion] == true,
      fallbackCause: json[ActivitySessionConstants.fallbackCause] as String?,
      isDeprecatedModel: json["bookmark_id"] != null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ActivitySessionConstants.activityId: activityId,
      ActivitySessionConstants.versionId: versionId,
      ActivitySessionConstants.usedFallbackVersion: usedFallbackVersion,
      ActivitySessionConstants.fallbackCause: fallbackCause,
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

  /// Target vocab lemmas, lower-cased, as a set for membership tests — used
  /// to highlight target words in messages and to track which target vocab
  /// has been used in a session. Callers in hot render loops should read this
  /// once and reuse it rather than per token (issue #7659).
  Set<String> get vocabLemmas =>
      vocab.map((v) => v.lemma.toLowerCase()).toSet();

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
      // Omit when null: the choreographer's Role schema defaults a missing
      // `goal` but 422s on an explicit null (v2 roles carry `goals` instead).
      if (goal != null) 'goal': goal,
      'avatar_url': avatarUrl,
      "goals": goals.map((g) => g.toJson()).toList(),
    };
  }
}

class ActivityRoleGoal {
  final String id;
  // Content-derived award identity from the choreo plan. The bot awards stars
  // on this (the Payload `id` re-mints on every edit), so star rendering keys
  // on it with an `id` fallback during the migration window. Null on
  // legacy/unmigrated goals.
  final String? goalSlug;
  final String description;

  const ActivityRoleGoal({
    required this.id,
    required this.description,
    this.goalSlug,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    if (goalSlug != null) "goal_slug": goalSlug,
    "description": description,
  };

  factory ActivityRoleGoal.fromJson(Map<String, dynamic> json) =>
      ActivityRoleGoal(
        id: json["id"],
        goalSlug: json["goal_slug"] as String?,
        description: json["description"],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityRoleGoal &&
          id == other.id &&
          goalSlug == other.goalSlug &&
          description == other.description;

  @override
  int get hashCode => id.hashCode ^ goalSlug.hashCode ^ description.hashCode;
}
