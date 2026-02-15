import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_selection.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:get_storage/get_storage.dart';

class _PracticeSelectionCacheEntry {
  final PracticeSelection selection;
  final DateTime timestamp;

  _PracticeSelectionCacheEntry({required this.selection, required this.timestamp});

  bool get isExpired => DateTime.now().difference(timestamp).inDays > 1;

  Map<String, dynamic> toJson() => {'selection': selection.toJson(), 'timestamp': timestamp.toIso8601String()};

  factory _PracticeSelectionCacheEntry.fromJson(Map<String, dynamic> json) {
    return _PracticeSelectionCacheEntry(
      selection: PracticeSelection.fromJson(json['selection']),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class PracticeSelectionRepo {
  static final GetStorage _storage = GetStorage('practice_selection_cache');

  static Future<PracticeSelection?> get(String eventId, String messageLanguage, List<PangeaToken> tokens) async {
    final userL2 = MatrixState.pangeaController.userController.userL2;
    if (userL2?.langCodeShort != messageLanguage.split("-").first) {
      return null;
    }

    final cached = _getCached(eventId);
    if (cached != null) return cached;

    final newEntry = await _fetch(tokens: tokens, langCode: messageLanguage);

    _setCached(eventId, newEntry);
    return newEntry;
  }

  static Future<PracticeSelection> _fetch({required List<PangeaToken> tokens, required String langCode}) async {
    if (langCode.split("-")[0] != MatrixState.pangeaController.userController.userL2?.langCodeShort) {
      return PracticeSelection({});
    }

    final eligibleTokens = tokens.where((t) => t.lemma.saveVocab).toList();
    if (eligibleTokens.isEmpty) {
      return PracticeSelection({});
    }
    final queue = await _fillActivityQueue(eligibleTokens, langCode.split('-')[0]);
    final selection = PracticeSelection(queue);
    return selection;
  }

  static PracticeSelection? _getCached(String eventId) {
    try {
      final keys = List.from(_storage.getKeys());
      for (final String key in keys) {
        final cacheEntry = _PracticeSelectionCacheEntry.fromJson(_storage.read(key));
        if (cacheEntry.isExpired) {
          _storage.remove(key);
        }
      }
    } catch (e) {
      _storage.erase();
      return null;
    }

    final entry = _storage.read(eventId);
    if (entry == null) return null;

    try {
      return _PracticeSelectionCacheEntry.fromJson(_storage.read(eventId)).selection;
    } catch (e) {
      _storage.remove(eventId);
      return null;
    }
  }

  static void _setCached(String eventId, PracticeSelection entry) {
    final cachedEntry = _PracticeSelectionCacheEntry(selection: entry, timestamp: DateTime.now());
    _storage.write(eventId, cachedEntry.toJson());
  }

  static Future<Map<ActivityTypeEnum, List<PracticeTarget>>> _fillActivityQueue(
    List<PangeaToken> tokens,
    String language,
  ) async {
    final queue = <ActivityTypeEnum, List<PracticeTarget>>{};
    for (final type in ActivityTypeEnum.practiceTypes) {
      queue[type] = await _buildActivity(type, tokens, language);
    }
    return queue;
  }

  static int _sortTokens(PangeaToken a, PangeaToken b, int aScore, int bScore) => bScore.compareTo(aScore);

  static int _sortMorphTargets(PracticeTarget a, PracticeTarget b, int aScore, int bScore) => bScore.compareTo(aScore);

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

  static Future<List<PracticeTarget>> _buildActivity(
    ActivityTypeEnum activityType,
    List<PangeaToken> tokens,
    String language,
  ) async {
    if (activityType == ActivityTypeEnum.morphId) {
      return _buildMorphActivity(tokens, language);
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

    final scores = await _fetchPriorityScores(practiceTokens, activityType, language);

    practiceTokens.sort((a, b) => _sortTokens(a, b, scores[a]!, scores[b]!));
    practiceTokens = practiceTokens.take(8).toList();
    practiceTokens.shuffle();

    return [
      PracticeTarget(
        activityType: activityType,
        tokens: practiceTokens.take(PracticeSelection.maxQueueLength).toList(),
      ),
    ];
  }

  static Future<List<PracticeTarget>> _buildMorphActivity(List<PangeaToken> tokens, String language) async {
    final List<PangeaToken> practiceTokens = List<PangeaToken>.from(tokens);
    final candidates = practiceTokens.expand(_tokenToMorphTargets).toList();
    final scores = await _fetchPriorityScores(practiceTokens, ActivityTypeEnum.morphId, language);
    candidates.sort((a, b) => _sortMorphTargets(a, b, scores[a.tokens.first]!, scores[b.tokens.first]!));

    final seenTexts = <String>{};
    final seenLemmas = <String>{};
    candidates.retainWhere(
      (target) =>
          seenTexts.add(target.tokens.first.text.content.toLowerCase()) &&
          seenLemmas.add(target.tokens.first.lemma.text.toLowerCase()),
    );
    return candidates.take(PracticeSelection.maxQueueLength).toList();
  }

  static Future<Map<PangeaToken, int>> _fetchPriorityScores(
    List<PangeaToken> tokens,
    ActivityTypeEnum activityType,
    String language,
  ) async {
    final scores = <PangeaToken, int>{};
    for (final token in tokens) {
      scores[token] = 0;
    }

    final ids = tokens.map((t) => t.vocabConstructID).toList();
    final idMap = {for (final token in tokens) token: token.vocabConstructID};

    final constructs = await MatrixState.pangeaController.matrixState.analyticsDataService.getConstructUses(
      ids,
      language,
    );

    for (final token in tokens) {
      final construct = constructs[idMap[token]];
      final lastUsed = construct?.lastUseByTypes(activityType.associatedUseTypes);

      final daysSinceLastUsed = lastUsed == null ? 20 : DateTime.now().difference(lastUsed).inDays;

      scores[token] = daysSinceLastUsed * (token.vocabConstructID.isContentWord ? 10 : 7);
    }
    return scores;
  }
}
