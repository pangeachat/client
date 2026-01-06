import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

class ConstructMergeTable {
  Map<String, Set<ConstructIdentifier>> lemmaTypeGroups = {};
  Map<ConstructIdentifier, ConstructIdentifier> otherToSpecific = {};

  void addConstructs(
    List<ConstructUses> constructs,
    Set<ConstructIdentifier> exclude,
  ) {
    addConstructsByUses(
      constructs.expand((c) => c.cappedUses).toList(),
      exclude,
    );
  }

  void addConstructsByUses(
    List<OneConstructUse> uses,
    Set<ConstructIdentifier> exclude,
  ) {
    for (final use in uses) {
      final id = use.identifier;
      if (exclude.contains(id)) continue;
      final composite = id.compositeKey;
      (lemmaTypeGroups[composite] ??= {}).add(id);
    }

    for (final use in uses) {
      if (exclude.contains(use.identifier)) continue;
      final id = use.identifier;
      final composite = id.compositeKey;
      if (id.category == 'other' && !otherToSpecific.containsKey(id)) {
        final specific = lemmaTypeGroups[composite]!.firstWhereOrNull(
          (k) => k.category != 'other',
        );
        if (specific != null) {
          otherToSpecific[id] = specific;
        }
      }
    }
  }

  void removeConstruct(ConstructIdentifier id) {
    final composite = id.compositeKey;
    final group = lemmaTypeGroups[composite];
    if (group == null) return;

    group.remove(id);
    if (group.isEmpty) {
      lemmaTypeGroups.remove(composite);
    }

    if (id.category != 'other') {
      final otherId = ConstructIdentifier(
        lemma: id.lemma,
        type: id.type,
        category: 'other',
      );
      otherToSpecific.remove(otherId);
    } else {
      otherToSpecific.remove(id);
    }
  }

  ConstructIdentifier resolve(ConstructIdentifier key) =>
      otherToSpecific[key] ?? key;

  List<ConstructIdentifier> groupedIds(
    ConstructIdentifier id,
    Set<ConstructIdentifier> exclude,
  ) {
    final keys = <ConstructIdentifier>[];
    if (!exclude.contains(id)) {
      keys.add(id);
    }

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

  void clear() {
    lemmaTypeGroups.clear();
    otherToSpecific.clear();
  }
}
