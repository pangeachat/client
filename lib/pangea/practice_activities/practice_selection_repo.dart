import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_selection.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _PracticeSelectionCacheEntry {
  final PracticeSelection selection;
  final DateTime timestamp;

  _PracticeSelectionCacheEntry({
    required this.selection,
    required this.timestamp,
  });

  bool get isExpired => DateTime.now().difference(timestamp).inDays > 1;

  Map<String, dynamic> toJson() => {
        'selection': selection.toJson(),
        'timestamp': timestamp.toIso8601String(),
      };

  factory _PracticeSelectionCacheEntry.fromJson(Map<String, dynamic> json) {
    return _PracticeSelectionCacheEntry(
      selection: PracticeSelection.fromJson(json['selection']),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class PracticeSelectionRepo {
  static final GetStorage _storage = GetStorage('practice_selection_cache');

  static PracticeSelection? get(
    String eventId,
    String messageLanguage,
    List<PangeaToken> tokens,
  ) {
    final userL2 = MatrixState.pangeaController.userController.userL2;
    if (userL2?.langCodeShort != messageLanguage.split("-").first) {
      return null;
    }

    final cached = _getCached(eventId);
    if (cached != null) return cached;

    final newEntry = _fetch(
      tokens: tokens,
      langCode: messageLanguage,
    );

    _setCached(eventId, newEntry);
    return newEntry;
  }

  static PracticeSelection _fetch({
    required List<PangeaToken> tokens,
    required String langCode,
  }) {
    if (langCode.split("-")[0] !=
        MatrixState.pangeaController.userController.userL2?.langCodeShort) {
      return PracticeSelection({});
    }

    final eligibleTokens = tokens.where((t) => t.lemma.saveVocab).toList();
    if (eligibleTokens.isEmpty) {
      return PracticeSelection({});
    }
    final queue = _fillActivityQueue(eligibleTokens);
    final selection = PracticeSelection(queue);
    return selection;
  }

  static PracticeSelection? _getCached(
    String eventId,
  ) {
    for (final String key in _storage.getKeys()) {
      try {
        final cacheEntry = _PracticeSelectionCacheEntry.fromJson(
          _storage.read(key),
        );
        if (cacheEntry.isExpired) {
          _storage.remove(key);
        }
      } catch (e) {
        _storage.remove(key);
      }
    }

    final entry = _storage.read(eventId);
    if (entry == null) return null;

    try {
      return _PracticeSelectionCacheEntry.fromJson(
        _storage.read(eventId),
      ).selection;
    } catch (e) {
      _storage.remove(eventId);
      return null;
    }
  }

  static void _setCached(
    String eventId,
    PracticeSelection entry,
  ) {
    final cachedEntry = _PracticeSelectionCacheEntry(
      selection: entry,
      timestamp: DateTime.now(),
    );
    _storage.write(eventId, cachedEntry.toJson());
  }

  static Map<ActivityTypeEnum, List<PracticeTarget>> _fillActivityQueue(
    List<PangeaToken> tokens,
  ) {
    final queue = <ActivityTypeEnum, List<PracticeTarget>>{};
    for (final type in ActivityTypeEnum.practiceTypes) {
      queue[type] = _buildActivity(type, tokens);
    }
    return queue;
  }

  static int _sortTokens(
    PangeaToken a,
    PangeaToken b,
    ActivityTypeEnum activityType,
  ) {
    final bScore = b.activityPriorityScore(activityType, null);
    final aScore = a.activityPriorityScore(activityType, null);
    return bScore.compareTo(aScore);
  }

  static int _sortMorphTargets(PracticeTarget a, PracticeTarget b) {
    final bScore = b.tokens.first.activityPriorityScore(
      ActivityTypeEnum.morphId,
      b.morphFeature!,
    );

    final aScore = a.tokens.first.activityPriorityScore(
      ActivityTypeEnum.morphId,
      a.morphFeature!,
    );

    return bScore.compareTo(aScore);
  }

  static List<PracticeTarget> _tokenToMorphTargets(PangeaToken t) {
    return t.morphsBasicallyEligibleForPracticeByPriority
        .map(
          (m) => PracticeTarget(
            tokens: [t],
            activityType: ActivityTypeEnum.morphId,
            morphFeature: MorphFeaturesEnumExtension.fromString(m.category),
          ),
        )
        .toList();
  }

  static List<PracticeTarget> _buildActivity(
    ActivityTypeEnum activityType,
    List<PangeaToken> tokens,
  ) {
    if (activityType == ActivityTypeEnum.morphId) {
      return _buildMorphActivity(tokens);
    }

    List<PangeaToken> practiceTokens = List<PangeaToken>.from(tokens);
    final seenTexts = <String>{};
    final seenLemmas = <String>{};
    practiceTokens.retainWhere(
      (token) =>
          token.eligibleForPractice(activityType) &&
          seenTexts.add(token.text.content.toLowerCase()) &&
          seenLemmas.add(token.lemma.text.toLowerCase()),
    );

    if (practiceTokens.length < activityType.minTokensForMatchActivity) {
      return [];
    }

    practiceTokens.sort((a, b) => _sortTokens(a, b, activityType));
    practiceTokens = practiceTokens.take(8).toList();
    practiceTokens.shuffle();

    return [
      PracticeTarget(
        activityType: activityType,
        tokens: practiceTokens.take(PracticeSelection.maxQueueLength).toList(),
      ),
    ];
  }

  static List<PracticeTarget> _buildMorphActivity(List<PangeaToken> tokens) {
    final List<PangeaToken> practiceTokens = List<PangeaToken>.from(tokens);
    final candidates = practiceTokens.expand(_tokenToMorphTargets).toList();
    candidates.sort(_sortMorphTargets);

    final seenTexts = <String>{};
    final seenLemmas = <String>{};
    candidates.retainWhere(
      (target) =>
          seenTexts.add(target.tokens.first.text.content.toLowerCase()) &&
          seenLemmas.add(target.tokens.first.lemma.text.toLowerCase()),
    );
    return candidates.take(PracticeSelection.maxQueueLength).toList();
  }
}
