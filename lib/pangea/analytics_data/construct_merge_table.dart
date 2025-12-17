import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

class LastUsedSummary {
  DateTime? lastUsed;
  final Map<ConstructUseTypeEnum, DateTime> lastUsedByType;
  final Map<String, DateTime> lastUsedByForm;

  LastUsedSummary({
    required this.lastUsedByType,
    required this.lastUsedByForm,
  });

  void setLastUsed(DateTime timestamp) {
    if (lastUsed == null || timestamp.isAfter(lastUsed!)) {
      lastUsed = timestamp;
    }
  }

  void setLastUsedByType(
    ConstructUseTypeEnum type,
    DateTime timestamp,
  ) {
    final existing = lastUsedByType[type];
    if (existing == null || timestamp.isAfter(existing)) {
      lastUsedByType[type] = timestamp;
    }
  }

  void setLastUsedByForm(
    String form,
    DateTime timestamp,
  ) {
    final existing = lastUsedByForm[form];
    if (existing == null || timestamp.isAfter(existing)) {
      lastUsedByForm[form] = timestamp;
    }
  }
}

class ConstructMergeTable {
  static final ConstructMergeTable instance = ConstructMergeTable._();
  ConstructMergeTable._();

  Map<String, Set<ConstructIdentifier>> lemmaTypeGroups = {};
  Map<ConstructIdentifier, ConstructIdentifier> otherToSpecific = {};
  Map<ConstructIdentifier, LastUsedSummary> lastUsedCache = {};

  void addConstructs(List<ConstructUses> constructs) {
    for (final construct in constructs) {
      addConstructsByUses(construct.uses);
    }
  }

  void addConstructsByUses(List<OneConstructUse> uses) {
    for (final use in uses) {
      final id = use.identifier;
      final composite = id.compositeKey;
      (lemmaTypeGroups[composite] ??= {}).add(id);

      lastUsedCache[id] ??= LastUsedSummary(
        lastUsedByType: {},
        lastUsedByForm: {},
      );
      lastUsedCache[id]!.setLastUsed(use.metadata.timeStamp);
      lastUsedCache[id]!.setLastUsedByType(use.useType, use.metadata.timeStamp);
      lastUsedCache[id]!.setLastUsedByForm(
        use.form ?? use.lemma,
        use.metadata.timeStamp,
      );

      if (id.category == 'other' && !otherToSpecific.containsKey(id)) {
        final specific = lemmaTypeGroups[composite]!.firstWhereOrNull(
          (k) => k != id && k.category != 'other',
        );
        if (specific != null) {
          otherToSpecific[id] = specific;
        }
      }
    }
  }

  ConstructIdentifier resolve(ConstructIdentifier key) =>
      otherToSpecific[key] ?? key;

  List<ConstructIdentifier> groupedIds(ConstructIdentifier id) {
    final keys = [id];

    if (id.category == 'other') {
      final specificKey = otherToSpecific[id];
      if (specificKey != null) {
        keys.add(specificKey);
      }
      return keys;
    }

    final group = lemmaTypeGroups[id.compositeKey];
    if (group == null) return keys;

    final otherEntry = group.firstWhereOrNull((k) => k.category == 'other');
    if (otherEntry == null) return keys;

    final otherSpecificEntry = otherToSpecific[otherEntry];
    if (otherSpecificEntry == id) {
      keys.add(
        ConstructIdentifier(
          lemma: id.lemma,
          type: id.type,
          category: 'other',
        ),
      );
    }
    return keys;
  }

  int uniqueConstructsByType(ConstructTypeEnum type) {
    final keys = lemmaTypeGroups.keys.where(
      (composite) => composite.endsWith('|${type.name}'),
    );

    int count = 0;
    for (final composite in keys) {
      final group = lemmaTypeGroups[composite]!;
      if (group.any((e) => e.category == 'other')) {
        // if this is the only entry in the group, it's a unique construct
        if (group.length == 1) {
          count += 1;
          continue;
        }
        // otherwise, count all but the 'other' entry,
        // which is merged into a more specific construct
        count += group.length - 1;
        continue;
      }

      // all specific constructs, count them all
      count += group.length;
    }

    return count;
  }

  bool constructUsed(ConstructIdentifier id) =>
      lemmaTypeGroups[id.compositeKey]?.contains(id) ?? false;

  LastUsedSummary? _getLastUsedSummary(ConstructIdentifier id) =>
      lastUsedCache[resolve(id)];

  DateTime? getLastUsedByForm(
    ConstructIdentifier id,
    String form,
  ) =>
      _getLastUsedSummary(id)?.lastUsedByForm[form];

  void clear() {
    lemmaTypeGroups.clear();
    otherToSpecific.clear();
    lastUsedCache.clear();
  }
}
