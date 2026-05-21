import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';

class ActivitySummaryAnalyticsModel {
  final Map<String, UserConstructAnalytics> constructs = {};

  ActivitySummaryAnalyticsModel();

  int totalUniqueConstructCount(ConstructTypeEnum type) {
    final ids = constructs.values
        .map((v) => v.usages.values)
        .expand((v) => v)
        .map((v) => v.identifier)
        .where((id) => id.type == type);

    return ids.toSet().length;
  }

  int get totalXP {
    int total = 0;
    for (final userAnalytics in constructs.values) {
      for (final usage in userAnalytics.usages.values) {
        total += usage.totalXP;
      }
    }
    return total;
  }

  /// Unique constructs of a given type for a specific user
  int _uniqueConstructCountForUser(String userId, ConstructTypeEnum type) {
    final userAnalytics = constructs[userId];
    if (userAnalytics == null) return 0;
    return userAnalytics.constructsOfType(type).length;
  }

  int _xpForUser(String userId) {
    final userAnalytics = constructs[userId];
    if (userAnalytics == null) return 0;

    int totalXP = 0;
    for (final usage in userAnalytics.usages.values) {
      totalXP += usage.totalXP;
    }
    return totalXP;
  }

  void addMessageConstructs(PangeaMessageEvent event) {
    final uses = event.originalSent?.vocabAndMorphUses;
    if (uses == null || uses.isEmpty) return;
    addConstructs(event.senderId, uses);
  }

  void addConstructs(String userId, List<OneConstructUse> uses) {
    final user = constructs[userId] ??= UserConstructAnalytics(userId);
    for (final use in uses) {
      user.addUsage(use);
    }

    constructs[userId] = user;
  }

  Map<String, List> generateSuperlatives() {
    final Map<String, List<String>> superlatives = {
      'vocab': [],
      'grammar': [],
      'xp': [],
    };
    // Find all user IDs
    final userIds = constructs.keys.toList();
    if (userIds.isEmpty) {
      return superlatives;
    }
    int maxVocab = 0;
    int maxGrammar = 0;
    int maxXp = 0;
    final Map<String, int> allVocabs = {};
    final Map<String, int> allGrammars = {};
    final Map<String, int> allXPs = {};

    for (final userId in userIds) {
      //vocab
      final vocabCount = _uniqueConstructCountForUser(
        userId,
        ConstructTypeEnum.vocab,
      );
      allVocabs[userId] = vocabCount;
      if (vocabCount > maxVocab) maxVocab = vocabCount;

      //grammar
      final grammarCount = _uniqueConstructCountForUser(
        userId,
        ConstructTypeEnum.morph,
      );
      allGrammars[userId] = grammarCount;
      if (grammarCount > maxGrammar) maxGrammar = grammarCount;

      //XP
      final xpCount = _xpForUser(userId);
      allXPs[userId] = xpCount;
      if (xpCount > maxXp) maxXp = xpCount;
    }
    superlatives['vocab'] = allVocabs.entries
        .where((e) => e.value == maxVocab && maxVocab > 0)
        .map((e) => e.key)
        .toList();

    superlatives['grammar'] = allGrammars.entries
        .where((e) => e.value == maxGrammar && maxGrammar > 0)
        .map((e) => e.key)
        .toList();

    superlatives['xp'] = allXPs.entries
        .where((e) => e.value == maxXp && maxXp > 0)
        .map((e) => e.key)
        .toList();
    return superlatives;
  }

  factory ActivitySummaryAnalyticsModel.fromJson(Map<String, dynamic> json) {
    final model = ActivitySummaryAnalyticsModel();
    for (final userEntry in json.entries) {
      final userId = userEntry.key;
      final constructList = userEntry.value as List<dynamic>;

      final userAnalytics = UserConstructAnalytics(userId);

      for (final constructJson in constructList) {
        final constructId = ConstructIdentifier.fromJson(constructJson);
        final timesUsed = constructJson['times_used'] as int? ?? 0;

        final usage = ConstructUsage(constructId)..totalXP = timesUsed;
        userAnalytics.usages[constructId.string] = usage;
      }

      model.constructs[userId] = userAnalytics;
    }

    return model;
  }

  Map<String, dynamic> toJson() => {
    for (final entry in constructs.entries) entry.key: entry.value.toJsonList(),
  };
}

class ConstructUsage {
  final ConstructIdentifier identifier;
  int totalXP;

  ConstructUsage(this.identifier) : totalXP = 0;

  void addTotalXP(int points) => totalXP += points;

  Map<String, dynamic> toJson() => {
    ...identifier.toJson(),
    'times_used': totalXP,
  };
}

class UserConstructAnalytics {
  final String userId;
  final Map<String, ConstructUsage> usages;

  UserConstructAnalytics(this.userId) : usages = {};

  /// Unique constructs of a given type
  Set<ConstructIdentifier> constructsOfType(ConstructTypeEnum type) => usages
      .values
      .map((u) => u.identifier)
      .where((id) => id.type == type)
      .toSet();

  void addUsage(OneConstructUse use) {
    final id = use.identifier;
    usages[id.string] ??= ConstructUsage(id);
    usages[id.string]!.addTotalXP(use.xp);
  }

  List<Map<String, dynamic>> toJsonList() =>
      usages.values.map((u) => u.toJson()).toList();
}
