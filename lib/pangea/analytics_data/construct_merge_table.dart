import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

class ConstructMergeTable {
  Map<String, Set<ConstructIdentifier>> lemmaTypeGroups = {};
  Map<ConstructIdentifier, ConstructIdentifier> otherToSpecific = {};
  final Map<ConstructIdentifier, ConstructIdentifier> caseInsensitive = {};

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
      final id = use.identifier;
      if (exclude.contains(id)) continue;
      final group = lemmaTypeGroups[id.compositeKey];
      if (group == null) continue;
      final matches = group.where((m) => m != id && m.string == id.string);
      for (final match in matches) {
        caseInsensitive[match] = id;
        caseInsensitive[id] = id;
      }
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
          otherToSpecific[id] = caseInsensitive[specific] ?? specific;
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

    final caseEntry = caseInsensitive[id];
    if (caseEntry != null && caseEntry != id) {
      caseInsensitive.remove(caseEntry);
    }
    caseInsensitive.remove(id);
  }

  ConstructIdentifier resolve(ConstructIdentifier key) {
    final specific = otherToSpecific[key] ?? key;
    return caseInsensitive[specific] ?? specific;
  }

  List<ConstructIdentifier> groupedIds(
    ConstructIdentifier id,
    Set<ConstructIdentifier> exclude,
  ) {
    final keys = <ConstructIdentifier>[];
    if (!exclude.contains(id)) {
      keys.add(id);
    }

    // if this key maps to a different case variant, include that as well
    final differentCase = caseInsensitive[id];
    if (differentCase != null && differentCase != id) {
      if (!exclude.contains(differentCase)) {
        keys.add(differentCase);
      }
    }

    // if this is an broad ('other') key, find the specific key it maps to
    // and include it if available
    if (id.category == 'other') {
      final specificKey = otherToSpecific[id];
      if (specificKey != null) {
        keys.add(specificKey);
      }
      return keys;
    }

    // if this is a specific key, and there existing an 'other' construct
    // in the same group, and that 'other' construct maps to this specific key,
    // include the 'other' construct as well
    final otherEntry = lemmaTypeGroups[id.compositeKey]
        ?.firstWhereOrNull((k) => k.category == 'other');
    if (otherEntry == null) {
      return keys;
    }

    if (otherToSpecific[otherEntry] == id) {
      keys.add(otherEntry);
    }
    return keys;
  }

  int uniqueConstructsByType(ConstructTypeEnum type) {
    final keys = lemmaTypeGroups.keys.where(
      (composite) => composite.endsWith('|${type.name}'),
    );

    final Set<ConstructIdentifier> unique = {};
    for (final composite in keys) {
      final group = lemmaTypeGroups[composite]!;
      unique.addAll(group.map((c) => resolve(c)));
    }

    return unique.length;
  }

  bool constructUsed(ConstructIdentifier id) =>
      lemmaTypeGroups[id.compositeKey]?.contains(id) ?? false;

  void clear() {
    lemmaTypeGroups.clear();
    otherToSpecific.clear();
    caseInsensitive.clear();
  }
}
