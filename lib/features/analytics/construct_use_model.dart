import 'dart:math';

import 'package:collection/collection.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_tier_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';

/// One lemma and a list of construct uses for that lemma
///
/// [_uses] is kept sorted chronologically at all times (oldest first). The
/// derived values that hot paths read repeatedly ([points], [cappedUses],
/// [cappedLastUse]) are memoized and invalidated by the only two mutators,
/// [addUses] and [merge] — see #8416.
class ConstructUses {
  List<OneConstructUse> _uses;
  final ConstructTypeEnum constructType;
  final String lemma;
  String? _category;

  ConstructUses({
    required List<OneConstructUse> uses,
    required this.constructType,
    required this.lemma,
    required category,
  }) : _category = category,
       _uses = List<OneConstructUse>.from(uses) {
    _sortUses();
  }

  /// Memoized sum of xp over all uses, capped at [AnalyticsConstants.xpForFlower].
  int? _pointsCache;

  /// Memoized length of the [cappedUses] prefix.
  int? _cappedLengthCache;

  void _invalidateDerived() {
    _pointsCache = null;
    _cappedLengthCache = null;
  }

  // Total points for all uses of this lemma
  int get points => _pointsCache ??= min(
    _uses.fold<int>(0, (total, use) => total + use.xp),
    AnalyticsConstants.xpForFlower,
  );

  DateTime? get lastUsed => _uses.lastOrNull?.timeStamp;

  DateTime? get cappedLastUse {
    final n = _cappedLength;
    return n == 0 ? null : _uses[n - 1].timeStamp;
  }

  String get category {
    if (_category == null || _category!.isEmpty) return "other";
    return _category!.toLowerCase();
  }

  bool get hasCorrectUse => _uses.any((use) => use.xp > 0);
  bool get hasIncorrectUse => _uses.any((use) => use.xp < 0);

  int get numTotalUses => _uses.length;

  ConstructIdentifier get id => ConstructIdentifier(
    lemma: lemma,
    type: constructType,
    category: category,
  );

  /// Get the lemma category, based on points
  ConstructLevelEnum get lemmaCategory {
    if (points < AnalyticsConstants.xpForGreens) {
      return ConstructLevelEnum.seeds;
    } else if (points >= AnalyticsConstants.xpForFlower) {
      return ConstructLevelEnum.flowers;
    }
    return ConstructLevelEnum.greens;
  }

  String get xpEmoji {
    if (points < 30) {
      // bean emoji
      return AnalyticsConstants.emojiForSeed;
    } else if (points < 100) {
      // sprout emoji
      return AnalyticsConstants.emojiForGreen;
    } else {
      // flower emoji
      return AnalyticsConstants.emojiForFlower;
    }
  }

  ConstructLevelEnum get constructLevel => switch (points) {
    < AnalyticsConstants.xpForGreens => ConstructLevelEnum.seeds,
    < AnalyticsConstants.xpForFlower => ConstructLevelEnum.greens,
    _ => ConstructLevelEnum.flowers,
  };

  /// Number of leading uses that make up [cappedUses]: the running xp total
  /// is accumulated in chronological order and the walk stops once it has
  /// reached the flower cap (the use that crosses the cap is included).
  int get _cappedLength {
    final cached = _cappedLengthCache;
    if (cached != null) return cached;

    var n = 0;
    var totalXp = 0;
    for (final use in _uses) {
      if (totalXp >= AnalyticsConstants.xpForFlower) break;
      totalXp += use.xp;
      n++;
    }
    return _cappedLengthCache = n;
  }

  /// The chronological prefix of uses that counted toward the cap. Returns a
  /// fresh list each call.
  List<OneConstructUse> get cappedUses => _uses.sublist(0, _cappedLength);

  /// Read-only view of all uses, sorted chronologically (oldest first).
  List<OneConstructUse> get uses => List.unmodifiable(_uses);

  /// Classify this construct into a [PracticeTier] based on use-type history.
  ///
  /// Walks uses in reverse chronological order to find the most recent
  /// chat use and any incorrect practice answers after it.
  PracticeTier get practiceTier {
    // Walk reverse chronologically. Everything seen before finding the
    // last chat use is more recent than that chat use.
    bool hasIncorrectAfterLastChatUse = false;

    for (int i = _uses.length - 1; i >= 0; i--) {
      final use = _uses[i];

      if (use.useType.isChatUse) {
        // Found the most recent chat use.
        if (use.useType == ConstructUseTypeEnum.wa &&
            !hasIncorrectAfterLastChatUse) {
          return PracticeTier.suppressed;
        }
        if (use.useType.isAssistedChatUse) {
          return PracticeTier.active;
        }
        // wa with incorrect after → active
        if (hasIncorrectAfterLastChatUse) {
          return PracticeTier.active;
        }
        return PracticeTier.maintenance;
      }

      if (use.useType.isIncorrectPractice) {
        hasIncorrectAfterLastChatUse = true;
      }
    }

    // No chat use found (only practice history).
    if (hasIncorrectAfterLastChatUse) return PracticeTier.active;
    return PracticeTier.maintenance;
  }

  DateTime? _lastUseByType(ConstructUseTypeEnum type) =>
      _uses.lastWhereOrNull((u) => u.useType == type)?.timeStamp;

  DateTime? _lastUseByTypes(List<ConstructUseTypeEnum> types) =>
      _uses.lastWhereOrNull((u) => types.contains(u.useType))?.timeStamp;

  /// Returns true when this construct should be skipped due to a recent
  /// correct answer for [exerciseType].
  ///
  /// If recent attempts have a high incorrect-answer ratio, the cooldown is
  /// bypassed so difficult constructs can reappear in the next session.
  bool shouldSkipForRecentPractice(
    PracticeExerciseTypeEnum exerciseType, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final cutoff = clock.subtract(
      AnalyticsPracticeConstants.recentPracticeCooldown,
    );

    final lastCorrectUse = _lastUseByType(exerciseType.correctUse);
    if (lastCorrectUse == null || !lastCorrectUse.isAfter(cutoff)) {
      return false;
    }

    final recentAttempts =
        _uses
            .where(
              (use) =>
                  exerciseType.associatedUseTypes.contains(use.useType) &&
                  use.timeStamp.isAfter(cutoff),
            )
            .toList()
          ..sort((a, b) => a.timeStamp.compareTo(b.timeStamp));

    // Strong recent success should end retries even if older attempts were
    // noisy (for example, several wrong taps before eventually getting it).
    final consecutiveCorrect = _consecutiveCorrectFromEnd(
      recentAttempts,
      exerciseType,
    );
    if (consecutiveCorrect >=
        AnalyticsPracticeConstants.consecutiveCorrectToEndRetry) {
      return true;
    }

    final attemptsCount = recentAttempts.length;
    if (attemptsCount <
        AnalyticsPracticeConstants.minAttemptsToBypassRecentCooldown) {
      return true;
    }

    final incorrectCount = recentAttempts
        .where((use) => use.useType == exerciseType.incorrectUse)
        .length;
    final incorrectRatio = incorrectCount / attemptsCount;

    final allowRetry =
        incorrectRatio >=
        AnalyticsPracticeConstants.incorrectRatioToBypassRecentCooldown;
    return !allowRetry;
  }

  int _consecutiveCorrectFromEnd(
    List<OneConstructUse> attempts,
    PracticeExerciseTypeEnum exerciseType,
  ) {
    var count = 0;

    for (int i = attempts.length - 1; i >= 0; i--) {
      final use = attempts[i].useType;

      if (use == exerciseType.correctUse) {
        count++;
        continue;
      }

      if (use == exerciseType.incorrectUse) {
        break;
      }
    }

    return count;
  }

  /// Compute priority score for this construct.
  ///
  /// Higher score = higher priority (should be practiced sooner).
  /// Suppressed-tier constructs return 0.
  ///
  /// When [exerciseType] is provided, recency is checked against that
  /// exercise's specific use types (e.g., corPA/incPA for wordMeaning).
  /// Otherwise, aggregate recency across all use types is used.
  int practiceScore({PracticeExerciseTypeEnum? exerciseType}) {
    final tier = practiceTier;
    if (tier == PracticeTier.suppressed) return 0;

    // Per-exercise-type recency when available, otherwise aggregate.
    final DateTime? lastUsedDate = exerciseType != null
        ? _lastUseByTypes(exerciseType.associatedUseTypes)
        : lastUsed;

    final daysSince = lastUsedDate == null
        ? AnalyticsConstants.defaultDaysSinceLastUsed
        : DateTime.now().difference(lastUsedDate).inDays;

    final wordMultiplier = id.isContentWord
        ? AnalyticsConstants.contentWordMultiplier
        : AnalyticsConstants.functionWordMultiplier;

    var score = daysSince * wordMultiplier;

    if (tier == PracticeTier.active) {
      score *= AnalyticsConstants.activeTierMultiplier;
    }

    return score;
  }

  Map<String, dynamic> toJson() {
    final json = {
      'construct_id': id.toJson(),
      'xp': points,
      'last_used': lastUsed?.toIso8601String(),
      'uses': _uses.map((e) => e.toJson()).toList(),
    };
    return json;
  }

  factory ConstructUses.fromJson(Map<String, dynamic> json) {
    final constructId = ConstructIdentifier.fromJson(
      Map<String, dynamic>.from(json['construct_id']),
    );

    List<dynamic> usesJson = [];
    if (json['uses'] is List) {
      usesJson = List<dynamic>.from(json['uses']);
    }

    final uses = usesJson
        .map((e) => OneConstructUse.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return ConstructUses(
      uses: uses,
      constructType: constructId.type,
      lemma: constructId.lemma,
      category: constructId.category,
    );
  }

  static int _byTime(OneConstructUse a, OneConstructUse b) =>
      a.timeStamp.compareTo(b.timeStamp);

  void _sortUses() {
    _uses.sort(_byTime);
    _invalidateDerived();
  }

  /// Merge an already-sorted [incoming] list into the sorted [_uses] in
  /// linear time. Existing uses win ties, so the result is stable.
  void _mergeSorted(List<OneConstructUse> incoming) {
    if (incoming.isEmpty) return;
    _invalidateDerived();

    // Common case: everything new is at least as recent as everything held.
    if (_uses.isEmpty ||
        !incoming.first.timeStamp.isBefore(_uses.last.timeStamp)) {
      _uses.addAll(incoming);
      return;
    }

    final merged = <OneConstructUse>[];
    var i = 0, j = 0;
    while (i < _uses.length && j < incoming.length) {
      if (_byTime(incoming[j], _uses[i]) < 0) {
        merged.add(incoming[j++]);
      } else {
        merged.add(_uses[i++]);
      }
    }
    if (i < _uses.length) merged.addAll(_uses.sublist(i));
    if (j < incoming.length) merged.addAll(incoming.sublist(j));
    _uses = merged;
  }

  void addUses(List<OneConstructUse> uses) {
    if (uses.isEmpty) return;
    final sorted = List<OneConstructUse>.from(uses)..sort(_byTime);
    _mergeSorted(sorted);
  }

  void merge(ConstructUses other) {
    if (other.lemma.toLowerCase() != lemma.toLowerCase() ||
        other.constructType != constructType) {
      throw ArgumentError(
        'Cannot merge ConstructUses with different lemmas or types',
      );
    }

    // other._uses is sorted by the class invariant.
    _mergeSorted(other._uses);

    if (category == 'other' && other.category != 'other') {
      _category = other.category;
    }
  }

  ConstructUses copyWith({
    List<OneConstructUse>? uses,
    ConstructTypeEnum? constructType,
    String? lemma,
    String? category,
  }) {
    return ConstructUses(
      uses: uses ?? _uses,
      constructType: constructType ?? this.constructType,
      lemma: lemma ?? this.lemma,
      category: category ?? _category,
    );
  }
}
