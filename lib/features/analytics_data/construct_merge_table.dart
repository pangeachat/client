import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';

class ConstructMergeTable {
  Map<String, Set<ConstructIdentifier>> lemmaTypeGroups = {};
  final Map<ConstructIdentifier, ConstructIdentifier> caseInsensitive = {};

  void addConstructsByUses(
    List<OneConstructUse> uses,
    Set<ConstructIdentifier> exclude,
  ) => addIdentifiers(uses.map((u) => u.identifier), exclude);

  /// Register [ids] (in order — order decides which case variant becomes
  /// canonical: the last one seen wins for its variants) and skip any that
  /// are in [exclude] or invalid.
  ///
  /// This is the whole merge-table input: [addConstructsByUses] only ever
  /// contributed each use's identifier, so the
  /// init path can feed identifiers read straight from the aggregate rows
  /// without deserializing their uses (see
  /// `AnalyticsDatabase.getAggregateIds`).
  void addIdentifiers(
    Iterable<ConstructIdentifier> ids,
    Set<ConstructIdentifier> exclude,
  ) {
    final accepted = <ConstructIdentifier>[];
    // Case-insensitive `string` → the ids sharing it inside their group, so
    // the second pass is a lookup rather than a scan of the group per id.
    final byString = <String, Set<ConstructIdentifier>>{};

    for (final id in ids) {
      if (exclude.contains(id) || id.isInvalid) continue;
      accepted.add(id);
      (lemmaTypeGroups[id.compositeKey] ??= {}).add(id);
    }
    if (accepted.isEmpty) return;
    _invalidateCounts();

    // Variants already in the table from earlier calls take part too.
    for (final id in accepted) {
      final group = lemmaTypeGroups[id.compositeKey];
      if (group == null) continue;
      for (final m in group) {
        (byString[m.string] ??= {}).add(m);
      }
    }

    for (final id in accepted) {
      final matches = byString[id.string];
      if (matches == null) continue;
      for (final match in matches) {
        if (match == id) continue;
        caseInsensitive[match] = id;
        caseInsensitive[id] = id;
      }
    }
  }

  void removeConstruct(ConstructIdentifier id) {
    _invalidateCounts();
    final composite = id.compositeKey;
    final group = lemmaTypeGroups[composite];
    if (group == null) return;

    group.remove(id);
    if (group.isEmpty) {
      lemmaTypeGroups.remove(composite);
    }

    final caseEntry = caseInsensitive[id];
    if (caseEntry != null && caseEntry != id) {
      caseInsensitive.remove(caseEntry);
    }
    caseInsensitive.remove(id);
  }

  ConstructIdentifier resolve(ConstructIdentifier key) {
    return caseInsensitive[key] ?? key;
  }

  List<ConstructIdentifier> groupedIds(
    ConstructIdentifier id,
    Set<ConstructIdentifier> exclude,
  ) {
    final keys = <ConstructIdentifier>[];
    if (exclude.contains(id) || id.isInvalid) {
      return keys;
    }

    keys.add(id);

    // if this key maps to a different case variant, include that as well
    final differentCase = caseInsensitive[id];
    if (differentCase != null && differentCase != id) {
      if (!exclude.contains(differentCase)) {
        keys.add(differentCase);
      }
    }

    return keys;
  }

  /// Memo of [uniqueConstructsByType] per type; cleared by every mutator.
  /// It is read in `build()` of the top-bar indicators and the world user
  /// cluster, where recomputing over every group per rebuild adds up.
  final Map<ConstructTypeEnum, int> _uniqueCountByType = {};

  void _invalidateCounts() => _uniqueCountByType.clear();

  int uniqueConstructsByType(ConstructTypeEnum type) =>
      _uniqueCountByType[type] ??= _computeUniqueConstructsByType(type);

  int _computeUniqueConstructsByType(ConstructTypeEnum type) {
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
    caseInsensitive.clear();
    _invalidateCounts();
  }
}
