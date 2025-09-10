import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';

class ActivitySummaryAnalyticsModel {
  final Map<String, UserConstructAnalytics> constructs = {};
  // Superlatives: {'vocab': [userId, ...], 'grammar': [userId, ...]}
  Map<String, List<String>> superlatives = {
    'vocab': [],
    'grammar': [],
  };

  ActivitySummaryAnalyticsModel();

  Map<ConstructTypeEnum, int> uniqueConstructCountsByType() {
    final Map<ConstructTypeEnum, Set<ConstructIdentifier>> typeToIds = {};

    for (final userAnalytics in constructs.values) {
      for (final usage in userAnalytics.usages.values) {
        final id = usage.identifier;
        typeToIds.putIfAbsent(id.type, () => <ConstructIdentifier>{}).add(id);
      }
    }

    return {
      for (final entry in typeToIds.entries) entry.key: entry.value.length,
    };
  }

  int uniqueConstructCount(ConstructTypeEnum type) =>
      uniqueConstructCountsByType()[type] ?? 0;

  /// Unique constructs of a given type for a specific user
  int uniqueConstructCountForUser(String userId, ConstructTypeEnum type) {
    final userAnalytics = constructs[userId];
    if (userAnalytics == null) return 0;
    return userAnalytics.constructsOfType(type).length;
  }

  void addConstructs(PangeaMessageEvent event) {
    final uses = event.originalSent?.vocabAndMorphUses();
    if (uses == null || uses.isEmpty) return;

    final user =
        constructs[event.senderId] ??= UserConstructAnalytics(event.senderId);

    for (final use in uses) {
      user.addUsage(use.identifier);
    }

    // Update superlatives after adding constructs
    _updateSuperlatives();
  }

  void _updateSuperlatives() {
    // Find all user IDs
    final userIds = constructs.keys.toList();
    if (userIds.isEmpty) {
      superlatives['vocab'] = [];
      superlatives['grammar'] = [];
      return;
    }
    int maxVocab = 0;
    final Map<String, int> vocabCounts = {};
    for (final userId in userIds) {
      final count =
          uniqueConstructCountForUser(userId, ConstructTypeEnum.vocab);
      vocabCounts[userId] = count;
      if (count > maxVocab) maxVocab = count;
    }
    superlatives['vocab'] = vocabCounts.entries
        .where((e) => e.value == maxVocab && maxVocab > 0)
        .map((e) => e.key)
        .toList();

    int maxGrammar = 0;
    final Map<String, int> grammarCounts = {};
    for (final userId in userIds) {
      final count =
          uniqueConstructCountForUser(userId, ConstructTypeEnum.morph);
      grammarCounts[userId] = count;
      if (count > maxGrammar) maxGrammar = count;
    }
    superlatives['grammar'] = grammarCounts.entries
        .where((e) => e.value == maxGrammar && maxGrammar > 0)
        .map((e) => e.key)
        .toList();
  }

  factory ActivitySummaryAnalyticsModel.fromJson(Map<String, dynamic> json) {
    final model = ActivitySummaryAnalyticsModel();
    final constructsJson = json['constructs'] ?? json;
    final superlativesJson = json['superlatives'] ?? {};

    for (final userEntry in constructsJson.entries) {
      final userId = userEntry.key;
      final constructList = userEntry.value as List<dynamic>;

      final userAnalytics = UserConstructAnalytics(userId);

      for (final constructJson in constructList) {
        final constructId = ConstructIdentifier.fromJson(constructJson);
        final timesUsed = constructJson['times_used'] as int? ?? 0;

        final usage = ConstructUsage(constructId)..timesUsed = timesUsed;
        userAnalytics.usages[constructId.string] = usage;
      }

      model.constructs[userId] = userAnalytics;
    }

    if (superlativesJson is Map) {
      model.superlatives['vocab'] =
          List<String>.from(superlativesJson['vocab'] ?? []);
      model.superlatives['grammar'] =
          List<String>.from(superlativesJson['grammar'] ?? []);
    }

    return model;
  }

  Map<String, dynamic> toJson() => {
        'constructs': {
          for (final entry in constructs.entries)
            entry.key: entry.value.toJsonList(),
        },
        'superlatives': superlatives,
      };
}

class ConstructUsage {
  final ConstructIdentifier identifier;
  int timesUsed;

  ConstructUsage(this.identifier) : timesUsed = 0;

  void increment() => timesUsed++;

  Map<String, dynamic> toJson() => {
        ...identifier.toJson(),
        'times_used': timesUsed,
      };
}

class UserConstructAnalytics {
  final String userId;
  final Map<String, ConstructUsage> usages;

  UserConstructAnalytics(this.userId) : usages = {};

  /// Unique constructs of a given type
  Set<ConstructIdentifier> constructsOfType(ConstructTypeEnum type) =>
      usages.values
          .map((u) => u.identifier)
          .where((id) => id.type == type)
          .toSet();

  void addUsage(ConstructIdentifier id) {
    usages[id.string] ??= ConstructUsage(id);
    usages[id.string]!.increment();
  }

  List<Map<String, dynamic>> toJsonList() =>
      usages.values.map((u) => u.toJson()).toList();
}
