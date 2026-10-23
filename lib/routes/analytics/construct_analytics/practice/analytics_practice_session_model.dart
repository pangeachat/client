import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

class ExampleMessageInfo {
  final List<InlineSpan> exampleMessage;

  /// The message offset of the first character of the spans' text (the
  /// ellipsis markers aside), so a token's offset maps to an index into that
  /// text as `offset - textOffset`. The slice starts at the message start
  /// when nothing was trimmed before the target, whatever the first token's
  /// offset is: a message may open with characters no token covers.
  final int textOffset;

  const ExampleMessageInfo({required this.exampleMessage, this.textOffset = 0});

  Map<String, dynamic> toJson() {
    final segments = <Map<String, dynamic>>[];

    for (final span in exampleMessage) {
      if (span is TextSpan) {
        segments.add({
          'text': span.text ?? '',
          'isBold': span.style?.fontWeight == FontWeight.bold,
        });
      }
    }

    return {'segments': segments, 'text_offset': textOffset};
  }

  factory ExampleMessageInfo.fromJson(Map<String, dynamic> json) {
    final segments = json['segments'] as List<dynamic>? ?? [];

    final spans = <InlineSpan>[];
    for (final segment in segments) {
      final text = segment['text'] as String? ?? '';
      final isBold = segment['isBold'] as bool? ?? false;

      spans.add(
        TextSpan(
          text: text,
          style: isBold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
      );
    }

    return ExampleMessageInfo(
      exampleMessage: spans,
      textOffset: json['text_offset'] as int? ?? 0,
    );
  }
}

/// An extended example message that includes both formatted display spans and tokens to generate audio analytics practice exercises.
/// eventId/roomId are needed for audio playback.
class AudioExampleMessage {
  final List<PangeaToken> tokens;
  final String? eventId;
  final String? roomId;
  final ExampleMessageInfo exampleMessage;

  const AudioExampleMessage({
    required this.tokens,
    this.eventId,
    this.roomId,
    required this.exampleMessage,
  });

  Map<String, dynamic> toJson() {
    return {'eventId': eventId, 'roomId': roomId};
  }

  factory AudioExampleMessage.fromJson(Map<String, dynamic> json) {
    return AudioExampleMessage(
      tokens: const [],
      eventId: json['eventId'] as String?,
      roomId: json['roomId'] as String?,
      exampleMessage: const ExampleMessageInfo(exampleMessage: []),
    );
  }
}

class AnalyticsPracticeTarget {
  final PracticeTarget target;
  final GrammarErrorRequestInfo? grammarErrorInfo;
  final ExampleMessageInfo? exampleMessage;
  final AudioExampleMessage? audioExampleMessage;

  AnalyticsPracticeTarget({
    required this.target,
    this.grammarErrorInfo,
    this.exampleMessage,
    this.audioExampleMessage,
  });

  Map<String, dynamic> toJson() => {
    'target': target.toJson(),
    'grammarErrorInfo': grammarErrorInfo?.toJson(),
    'exampleMessage': exampleMessage?.toJson(),
    'audioExampleMessage': audioExampleMessage?.toJson(),
  };

  factory AnalyticsPracticeTarget.fromJson(Map<String, dynamic> json) =>
      AnalyticsPracticeTarget(
        target: PracticeTarget.fromJson(json['target']),
        grammarErrorInfo: json['grammarErrorInfo'] != null
            ? GrammarErrorRequestInfo.fromJson(json['grammarErrorInfo'])
            : null,
        exampleMessage: json['exampleMessage'] != null
            ? ExampleMessageInfo.fromJson(json['exampleMessage'])
            : null,
        audioExampleMessage: json['audioExampleMessage'] != null
            ? AudioExampleMessage.fromJson(json['audioExampleMessage'])
            : null,
      );
}

/// One word a vocab session practices, picked once when its start page opens,
/// with the exercise types that can be made for it. The start page's chips
/// only decide which of those it gets (practice-exercises.instructions.md,
/// "Start page").
class PracticeWord {
  final PangeaToken token;
  final Set<LearningSkillsEnum> skills;

  /// Wrong answers for its meaning exercise, for a word from a Mission plan.
  final List<ConstructIdentifier> distractorCandidates;

  const PracticeWord({
    required this.token,
    required this.skills,
    this.distractorCandidates = const [],
  });

  AnalyticsPracticeTarget targetFor(LearningSkillsEnum skill) =>
      AnalyticsPracticeTarget(
        target: PracticeTarget(
          tokens: [token],
          exerciseType: switch (skill) {
            LearningSkillsEnum.hearing => PracticeExerciseTypeEnum.lemmaAudio,
            LearningSkillsEnum.speaking => PracticeExerciseTypeEnum.readAloud,
            _ => PracticeExerciseTypeEnum.lemmaMeaning,
          },
          distractorCandidates: skill == LearningSkillsEnum.reading
              ? distractorCandidates
              : const [],
        ),
      );
}

class AnalyticsPracticeSessionModel {
  /// Wall-clock zero, stamped by [markStarted] when the first exercise is on
  /// screen — NOT when the session's targets were picked. Null until then, so
  /// a slow first generation never spends the learner's speed bonus before
  /// they can answer anything (#8966). See
  /// practice-exercises.instructions.md § Loading & Generation Sequencing.
  DateTime? startedAt;

  final ConstructTypeEnum type;
  final List<AnalyticsPracticeTarget> practiceTargets;
  final String userL1;
  final String userL2;

  /// The Mission this session is scoped to and its can-do statement, for the
  /// panel's header (#9438); both null for an unscoped session.
  final String? missionId;
  final String? missionLabel;

  /// Started while the app could not reach Pangea, so built only from what
  /// this device has. Kept for the whole session. See
  /// practice-exercises.instructions.md, "Offline Practice".
  final bool offline;

  /// The exercise types this vocab session practices, and those this device
  /// had words for when it was picked, for the start page's chips; both
  /// empty for grammar. See practice-exercises.instructions.md, "Start page".
  final Set<LearningSkillsEnum> skills;
  final Set<LearningSkillsEnum> availableSkills;

  /// A vocab session's words, in the order picked; empty for grammar.
  final List<PracticeWord> words;

  /// How many exercises the session plans to show, when fewer than
  /// [AnalyticsPracticeConstants.practiceGroupSize] because some of its words
  /// have no exercise among the start page's chips.
  final int? plannedSize;

  AnalyticsPracticeSessionState state;

  AnalyticsPracticeSessionModel({
    this.startedAt,
    required this.type,
    required this.practiceTargets,
    required this.userL1,
    required this.userL2,
    this.missionId,
    this.missionLabel,
    this.offline = false,
    this.skills = const {},
    this.availableSkills = const {},
    this.words = const [],
    this.plannedSize,
    AnalyticsPracticeSessionState? state,
  }) : state = state ?? const AnalyticsPracticeSessionState();

  /// A vocab session over [words]: the first
  /// [AnalyticsPracticeConstants.practiceGroupSize] are the ones it plans to
  /// show and the rest are spares. It practices the [skills] its planned
  /// words can take, or all of those when none of [skills] can be. A word
  /// left with no exercise drops out, and no spare takes its place.
  factory AnalyticsPracticeSessionModel.vocab({
    required List<PracticeWord> words,
    required Set<LearningSkillsEnum> skills,
    required String userL1,
    required String userL2,
    String? missionId,
    String? missionLabel,
    bool offline = false,
  }) {
    final groupSize = AnalyticsPracticeConstants.practiceGroupSize;
    final available = {
      for (final word in words.take(groupSize)) ...word.skills,
    };
    var practiced = skills.intersection(available);
    if (practiced.isEmpty) practiced = available;
    final planned = [
      for (final word in words.take(groupSize))
        if (word.skills.any(practiced.contains)) word,
    ];
    final spares = [
      for (final word in words.skip(groupSize))
        if (word.skills.any(practiced.contains)) word,
    ];
    return AnalyticsPracticeSessionModel(
      type: ConstructTypeEnum.vocab,
      practiceTargets: dealSkills([...planned, ...spares], practiced),
      userL1: userL1,
      userL2: userL2,
      missionId: missionId,
      missionLabel: missionLabel,
      offline: offline,
      skills: practiced,
      availableSkills: available,
      words: words,
      plannedSize: planned.length,
    );
  }

  /// The same words dealt for other start page chips.
  AnalyticsPracticeSessionModel withSkills(Set<LearningSkillsEnum> skills) =>
      AnalyticsPracticeSessionModel.vocab(
        words: words,
        skills: skills,
        userL1: userL1,
        userL2: userL2,
        missionId: missionId,
        missionLabel: missionLabel,
        offline: offline,
      );

  /// Listening first on a tie, then speaking, so the two take turns.
  static const List<LearningSkillsEnum> _dealOrder = [
    LearningSkillsEnum.hearing,
    LearningSkillsEnum.speaking,
    LearningSkillsEnum.reading,
  ];

  /// One exercise per word: each gets the type among [skills] it can take
  /// that has been dealt least so far. An even share keeps speaking in every
  /// session that has it on without an item that needs a microphone and the
  /// network dominating it (practice-exercises.instructions.md, "Speaking
  /// practice").
  @visibleForTesting
  static List<AnalyticsPracticeTarget> dealSkills(
    List<PracticeWord> words,
    Set<LearningSkillsEnum> skills,
  ) {
    final dealt = <LearningSkillsEnum, int>{};
    final targets = <AnalyticsPracticeTarget>[];
    for (final word in words) {
      LearningSkillsEnum? pick;
      for (final skill in _dealOrder) {
        if (!skills.contains(skill) || !word.skills.contains(skill)) continue;
        if (pick == null || (dealt[skill] ?? 0) < (dealt[pick] ?? 0)) {
          pick = skill;
        }
      }
      if (pick == null) continue;
      dealt[pick] = (dealt[pick] ?? 0) + 1;
      targets.add(word.targetFor(pick));
    }
    return targets;
  }

  // Maximum activities to attempt (including skips)
  int get _maxAttempts => AnalyticsPracticeConstants.targetsToGenerate
      .clamp(0, practiceTargets.length)
      .toInt();

  int get _completionGoal =>
      (plannedSize ?? AnalyticsPracticeConstants.practiceGroupSize).clamp(
        0,
        practiceTargets.length,
      );

  // Total attempted so far (completed + skipped)
  int get _totalAttempted => state.currentIndex + state.skippedActivities;

  bool get isComplete {
    final complete =
        state.finished ||
        state.currentIndex >= _completionGoal ||
        _totalAttempted >= _maxAttempts;
    return complete;
  }

  bool get loadFailed => isComplete && state.currentIndex == 0;

  /// The distinct words (vocab) or grammar points among the exercises the
  /// session plans to show, which the start page counts. A spare standing in
  /// for a failed or skipped exercise can change them a little.
  List<PracticeTarget> get plannedPoints {
    final seen = <Object>{};
    return [
      for (final planned in practiceTargets.take(_completionGoal))
        if (seen.add(
          type == ConstructTypeEnum.vocab
              ? planned.target.tokens.first.vocabConstructID
              : planned.target,
        ))
          planned.target,
    ];
  }

  double get progress {
    final possibleCompletions =
        (state.currentIndex + _maxAttempts - _totalAttempted).clamp(
          0,
          _completionGoal,
        );
    return possibleCompletions > 0
        ? (state.currentIndex / possibleCompletions).clamp(0.0, 1.0)
        : 1.0;
  }

  List<MessagePracticeExerciseRequest> get exerciseRequests {
    return practiceTargets.map((target) {
      return MessagePracticeExerciseRequest(
        userL1: userL1,
        userL2: userL2,
        exerciseQualityFeedback: null,
        target: target.target,
        grammarErrorInfo: target.grammarErrorInfo,
        exampleMessage: target.exampleMessage,
        audioExampleMessage: target.audioExampleMessage,
        offline: offline,
      );
    }).toList();
  }

  /// Returns congratulations message based on performance
  String getCompletionMessage(BuildContext context) {
    final hasTimeBonus =
        state.bonusClockSeconds <= AnalyticsPracticeConstants.timeForBonus;
    final hintsUsed = state.hintsUsed;

    final bool perfectAccuracy = state.accuracy == 100;
    final bool noHintsUsed = hintsUsed == 0;
    final bool hintsAvailable = type == ConstructTypeEnum.morph;

    //check how many conditions for bonuses the user met and return message accordingly
    final conditionsMet = [
      perfectAccuracy,
      !hintsAvailable || noHintsUsed,
      hasTimeBonus,
    ].where((c) => c).length;

    if (conditionsMet == 3) {
      return L10n.of(context).perfectPractice;
    }
    if (conditionsMet >= 2) {
      return L10n.of(context).greatPractice;
    }
    if (hintsAvailable && noHintsUsed) {
      return L10n.of(context).usedNoHints;
    }
    return L10n.of(context).youveCompletedPractice;
  }

  /// Start the clock, once. Idempotent because every exercise after the first
  /// arrives through the same path.
  void markStarted() => startedAt ??= DateTime.now();

  void setElapsedSeconds(int seconds) =>
      state = state.copyWith(elapsedSeconds: seconds);

  /// Time a read-aloud item was on screen. It stays on the displayed clock but
  /// is taken off the speed bonus, because rushing a read defeats the point
  /// (practice-exercises.instructions.md, "Scoring").
  void addReadAloudSeconds(int seconds) => state = state.copyWith(
    readAloudSeconds: state.readAloudSeconds + seconds,
  );

  /// Ends the session and fixes its bonus uses, so the ones recorded are the
  /// ones the completion view measures.
  void finishSession() =>
      state = state.copyWith(finished: true, bonusUses: state.earnedBonusUses);

  void completeExercise() =>
      state = state.copyWith(currentIndex: state.currentIndex + 1);

  void incrementSkippedActivities() =>
      state = state.copyWith(skippedActivities: state.skippedActivities + 1);

  void submitAnswer(List<OneConstructUse> uses) =>
      state = state.copyWith(completedUses: [...state.completedUses, ...uses]);

  void useHint() => state = state.copyWith(hintsUsed: state.hintsUsed + 1);

  factory AnalyticsPracticeSessionModel.fromJson(Map<String, dynamic> json) {
    return AnalyticsPracticeSessionModel(
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      type: ConstructTypeEnum.values.firstWhere(
        (e) => e.name == json['type'] as String,
        orElse: () => ConstructTypeEnum.vocab,
      ),
      practiceTargets: (json['practiceTargets'] as List<dynamic>)
          .map((e) => AnalyticsPracticeTarget.fromJson(e))
          .whereType<AnalyticsPracticeTarget>()
          .toList(),
      userL1: json['userL1'] as String,
      userL2: json['userL2'] as String,
      missionId: json['missionId'] as String?,
      missionLabel: json['missionLabel'] as String?,
      offline: json['offline'] as bool? ?? false,
      state: AnalyticsPracticeSessionState.fromJson(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startedAt': startedAt?.toIso8601String(),
      'type': type.name,
      'practiceTargets': practiceTargets.map((e) => e.toJson()).toList(),
      'userL1': userL1,
      'userL2': userL2,
      if (missionId != null) 'missionId': missionId,
      if (missionLabel != null) 'missionLabel': missionLabel,
      'offline': offline,
      ...state.toJson(),
    };
  }
}

class AnalyticsPracticeSessionState {
  final List<OneConstructUse> completedUses;
  final int currentIndex;
  final bool finished;

  final int hintsUsed;
  final int elapsedSeconds;
  final int skippedActivities;

  /// Seconds spent on read-aloud items, excluded from the speed bonus.
  final int readAloudSeconds;

  /// The bonus uses recorded when the session finished; empty until then.
  final List<OneConstructUse> bonusUses;

  const AnalyticsPracticeSessionState({
    this.completedUses = const [],
    this.currentIndex = 0,
    this.finished = false,
    this.hintsUsed = 0,
    this.elapsedSeconds = 0,
    this.skippedActivities = 0,
    this.readAloudSeconds = 0,
    this.bonusUses = const [],
  });

  /// The clock the speed bonus is judged on: elapsed time less the time
  /// read-aloud items were on screen.
  int get bonusClockSeconds => elapsedSeconds - readAloudSeconds;

  /// Every use the session recorded: its answers, then its bonuses.
  List<OneConstructUse> get recordedUses => [...completedUses, ...bonusUses];

  double get accuracy {
    if (completedUses.isEmpty) return 0.0;
    final correct = completedUses.where((use) => use.xp > 0).length;
    final result = correct / completedUses.length;
    return (result * 100).truncateToDouble();
  }

  bool get _giveAccuracyBonus => accuracy >= 100.0;

  bool get _giveTimeBonus =>
      bonusClockSeconds <= AnalyticsPracticeConstants.timeForBonus;

  int get accuracyBonusXP => _giveAccuracyBonus ? _bonusXP : 0;

  int get timeBonusXP => _giveTimeBonus ? _bonusXP : 0;

  int get _bonusXP => _bonusUses.fold(0, (sum, use) => sum + use.xp);

  List<OneConstructUse> get _bonusUses =>
      completedUses.where((use) => use.xp > 0).map(_bonusUse).toList();

  /// The bonus uses the answers so far earn, freshly stamped on each read;
  /// [AnalyticsPracticeSessionModel.finishSession] fixes them as [bonusUses].
  List<OneConstructUse> get earnedBonusUses => [
    if (_giveAccuracyBonus) ..._bonusUses,
    if (_giveTimeBonus) ..._bonusUses,
  ];

  OneConstructUse _bonusUse(OneConstructUse originalUse) => OneConstructUse(
    useType: ConstructUseTypeEnum.bonus,
    constructType: originalUse.constructType,
    metadata: ConstructUseMetaData(
      roomId: originalUse.metadata.roomId,
      timeStamp: DateTime.now(),
    ),
    category: originalUse.category,
    lemma: originalUse.lemma,
    form: originalUse.form,
    xp: ConstructUseTypeEnum.bonus.pointValue,
  );

  AnalyticsPracticeSessionState copyWith({
    List<OneConstructUse>? completedUses,
    int? currentIndex,
    bool? finished,
    int? hintsUsed,
    int? elapsedSeconds,
    int? skippedActivities,
    int? readAloudSeconds,
    List<OneConstructUse>? bonusUses,
  }) {
    return AnalyticsPracticeSessionState(
      completedUses: completedUses ?? this.completedUses,
      currentIndex: currentIndex ?? this.currentIndex,
      finished: finished ?? this.finished,
      hintsUsed: hintsUsed ?? this.hintsUsed,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      skippedActivities: skippedActivities ?? this.skippedActivities,
      readAloudSeconds: readAloudSeconds ?? this.readAloudSeconds,
      bonusUses: bonusUses ?? this.bonusUses,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completedUses': completedUses.map((e) => e.toJson()).toList(),
      'currentIndex': currentIndex,
      'finished': finished,
      'hintsUsed': hintsUsed,
      'elapsedSeconds': elapsedSeconds,
      'skippedActivities': skippedActivities,
      'readAloudSeconds': readAloudSeconds,
      'bonusUses': bonusUses.map((e) => e.toJson()).toList(),
    };
  }

  factory AnalyticsPracticeSessionState.fromJson(Map<String, dynamic> json) {
    return AnalyticsPracticeSessionState(
      completedUses: _usesFromJson(json['completedUses']),
      currentIndex: json['currentIndex'] as int? ?? 0,
      finished: json['finished'] as bool? ?? false,
      hintsUsed: json['hintsUsed'] as int? ?? 0,
      elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
      skippedActivities: json['skippedActivities'] as int? ?? 0,
      readAloudSeconds: json['readAloudSeconds'] as int? ?? 0,
      bonusUses: _usesFromJson(json['bonusUses']),
    );
  }

  static List<OneConstructUse> _usesFromJson(Object? json) =>
      (json as List<dynamic>?)
          ?.map((e) => OneConstructUse.fromJson(e))
          .whereType<OneConstructUse>()
          .toList() ??
      [];
}
