import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_selection_repo.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PracticeSelection {
  late String _userL1;
  late String _userL2;
  final DateTime createdAt = DateTime.now();

  late final List<PangeaToken> _tokens;

  final Map<ActivityTypeEnum, List<PracticeTarget>> _activityQueue = {};

  final int _maxQueueLength = 5;

  PracticeSelection({
    required List<PangeaToken> tokens,
    String? userL1,
    String? userL2,
  }) {
    _userL1 = userL1 ??
        MatrixState.pangeaController.languageController.userL1?.langCode ??
        LanguageKeys.defaultLanguage;
    _userL2 = userL2 ??
        MatrixState.pangeaController.languageController.userL2?.langCode ??
        LanguageKeys.defaultLanguage;
    _tokens = tokens;
    initialize();
  }

  List<PangeaToken> get tokens => _tokens;

  String get messageText => PangeaToken.reconstructText(tokens);

  Map<String, dynamic> toJson() => {
        'createdAt': createdAt.toIso8601String(),
        'tokens': _tokens.map((t) => t.toJson()).toList(),
        'activityQueue': _activityQueue.map(
          (key, value) => MapEntry(
            key.toString(),
            value.map((e) => e.toJson()).toList(),
          ),
        ),
      };

  static PracticeSelection fromJson(Map<String, dynamic> json) {
    return PracticeSelection(
      tokens:
          (json['tokens'] as List).map((t) => PangeaToken.fromJson(t)).toList(),
    ).._activityQueue.addAll(
        (json['activityQueue'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            ActivityTypeEnum.values.firstWhere((e) => e.toString() == key),
            (value as List).map((e) => PracticeTarget.fromJson(e)).toList(),
          ),
        ),
      );
  }

  void _pushQueue(PracticeTarget entry) {
    if (_activityQueue.containsKey(entry.activityType)) {
      _activityQueue[entry.activityType]!.insert(0, entry);
    } else {
      _activityQueue[entry.activityType] = [entry];
    }

    // just in case we make a mistake and the queue gets too long
    if (_activityQueue[entry.activityType]!.length > _maxQueueLength) {
      debugger(when: kDebugMode);
      _activityQueue[entry.activityType]!.removeRange(
        _maxQueueLength,
        _activityQueue.length,
      );
    }
  }

  PracticeTarget? nextActivity(ActivityTypeEnum a) =>
      _activityQueue[a]?.firstOrNull;

  bool get hasHiddenWordActivity =>
      activities(ActivityTypeEnum.hiddenWordListening).isNotEmpty;

  bool get hasMessageMeaningActivity =>
      activities(ActivityTypeEnum.messageMeaning).isNotEmpty;

  int get numActivities => _activityQueue.length;

  List<PracticeTarget> activities(ActivityTypeEnum a) =>
      _activityQueue[a] ?? [];

  // /// If there are more than 4 tokens that can be heard, we don't want to do word focus listening
  // /// Otherwise, we don't have enough distractors
  // bool get canDoWordFocusListening =>
  //     _tokens.where((t) => t.canBeHeard).length > 4;

  PracticeTarget buildActivity(ActivityTypeEnum activityType) {
    final List<PangeaToken> tokens =
        _tokens.where((t) => t.lemma.saveVocab).sorted(
              (a, b) => b.activityPriorityScore(activityType, null).compareTo(
                    a.activityPriorityScore(activityType, null),
                  ),
            );
    // debugPrint('emoji activity priority score: ${tokens.map(
    //   (e) => e.activityPriorityScore(activityType, null),
    // )}');

    return PracticeTarget(
      activityType: activityType,
      tokens: tokens.take(_maxQueueLength).shuffled().toList(),
      userL2: _userL2,
    );
  }

  /// On initialization, we pick which tokens to do activities on and what types of activities to do
  void initialize() {
    final eligibleTokens = _tokens.where((t) => t.lemma.saveVocab);

    // EMOJI
    // sort the tokens by the preference of them for an emoji activity
    // order from least to most recent
    // words that have never been used are counted as 1000 days
    // we preference content words over function words by multiplying the days since last use by 2
    // NOTE: for now, we put it at the end if it has no uses and basically just give them the answer
    // later on, we may introduce an emoji activity that is easier than the current matching one
    // i.e. we show them 3 good emojis and 1 bad one and ask them to pick the bad one
    _activityQueue[ActivityTypeEnum.emoji] = [
      buildActivity(ActivityTypeEnum.emoji),
    ];

    // WORD MEANING
    // make word meaning activities
    // same as emojis for now
    _activityQueue[ActivityTypeEnum.wordMeaning] = [
      buildActivity(ActivityTypeEnum.wordMeaning),
    ];

    // WORD FOCUS LISTENING
    // make word focus listening activities
    // same as emojis for now
    _activityQueue[ActivityTypeEnum.wordFocusListening] = [
      buildActivity(ActivityTypeEnum.wordFocusListening),
    ];

    // GRAMMAR
    // build a list of TargetTokensAndActivityType for all tokens and all features in the message
    // limits to _maxQueueLength activities and only one per token
    final List<PracticeTarget> candidates = eligibleTokens.expand(
      (t) {
        return t.morphsBasicallyEligibleForPracticeByPriority.map(
          (m) => PracticeTarget(
            tokens: [t],
            activityType: ActivityTypeEnum.morphId,
            morphFeature: MorphFeaturesEnumExtension.fromString(m.category),
            userL2: _userL2,
          ),
        );
      },
    ).sorted(
      (a, b) => b.tokens.first
          .activityPriorityScore(
            ActivityTypeEnum.morphId,
            b.morphFeature!,
          )
          .compareTo(
            a.tokens.first.activityPriorityScore(
              ActivityTypeEnum.morphId,
              a.morphFeature!,
            ),
          ),
    );
    //pick from the top 5, only including one per token
    _activityQueue[ActivityTypeEnum.morphId] = [];
    for (final candidate in candidates) {
      if (_activityQueue[ActivityTypeEnum.morphId]!.length >= _maxQueueLength) {
        break;
      }
      if (_activityQueue[ActivityTypeEnum.morphId]?.any(
            (entry) => entry.tokens.contains(candidate.tokens.first),
          ) ==
          false) {
        _activityQueue[ActivityTypeEnum.morphId]?.add(candidate);
      }
    }

    PracticeSelectionRepo.save(this);
  }

  PracticeTarget? getSelection(
    ActivityTypeEnum a, [
    PangeaToken? t,
    MorphFeaturesEnum? morph,
  ]) {
    if (a == ActivityTypeEnum.morphId && (t == null || morph == null)) {
      return null;
    }
    return _activityQueue[a]?.firstWhereOrNull(
      (entry) =>
          (t == null || entry.tokens.contains(t)) &&
          (morph == null || entry.morphFeature == morph),
    );
  }

  bool hasActivity(
    ActivityTypeEnum a, [
    PangeaToken? t,
    MorphFeaturesEnum? morph,
  ]) =>
      getSelection(a, t, morph) != null;

  /// Add a message meaning activity to the front of the queue
  /// And limits to _maxQueueLength activities
  void addMessageMeaningActivity() {
    final entry = PracticeTarget(
      tokens: _tokens,
      activityType: ActivityTypeEnum.messageMeaning,
      userL2: _userL2,
    );
    _pushQueue(entry);
  }

  void exitPracticeFlow() {
    _activityQueue.clear();
    PracticeSelectionRepo.save(this);
  }

  void revealAllTokens() {
    _activityQueue[ActivityTypeEnum.hiddenWordListening]?.clear();
    PracticeSelectionRepo.save(this);
  }

  bool isTokenInHiddenWordActivity(PangeaToken token) =>
      _activityQueue[ActivityTypeEnum.hiddenWordListening]?.isNotEmpty ?? false;

  Future<List<LemmaInfoResponse>> getLemmaInfoForActivityTokens() async {
    // make a list of unique tokens in emoji and wordMeaning activities
    final List<PangeaToken> uniqueTokens = [];
    for (final t in _activityQueue[ActivityTypeEnum.emoji] ?? []) {
      if (!uniqueTokens.contains(t.tokens.first)) {
        uniqueTokens.add(t.tokens.first);
      }
    }
    for (final t in _activityQueue[ActivityTypeEnum.wordMeaning] ?? []) {
      if (!uniqueTokens.contains(t.tokens.first)) {
        uniqueTokens.add(t.tokens.first);
      }
    }

    // get the lemma info for each token
    final List<Future<LemmaInfoResponse>> lemmaInfoFutures = [];
    for (final t in uniqueTokens) {
      lemmaInfoFutures.add(t.vocabConstructID.getLemmaInfo());
    }

    return Future.wait(lemmaInfoFutures);
  }
}
