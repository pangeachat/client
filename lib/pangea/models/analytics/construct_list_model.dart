import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fluffychat/pangea/enum/construct_type_enum.dart';
import 'package:fluffychat/pangea/models/analytics/construct_use_model.dart';
import 'package:fluffychat/pangea/models/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/practice_activity_model.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// A wrapper around a list of [OneConstructUse]s, used to simplify
/// the process of filtering / sorting / displaying the events.
class ConstructListModel {
  void dispose() {
    _constructMap = {};
    _constructList = [];
    prevXP = 0;
    totalXP = 0;
    level = 0;
    vocabLemmas = 0;
    grammarLemmas = 0;
    _uses.clear();
  }

  List<OneConstructUse> _uses = [];
  List<OneConstructUse> get uses => _uses;

  /// A map of lemmas to ConstructUses, each of which contains a lemma
  /// key = lemmma + constructType.string, value = ConstructUses
  Map<String, ConstructUses> _constructMap = {};

  /// Storing this to avoid re-running the sort operation each time this needs to
  /// be accessed. It contains the same information as _constructMap, but sorted.
  List<ConstructUses> _constructList = [];

  /// A map of categories to lists of ConstructUses
  Map<String, List<ConstructUses>> _categoriesToUses = {};

  /// Analytics data consumed by widgets. Updated each time new analytics come in.
  int prevXP = 0;
  int totalXP = 0;
  int level = 0;
  int vocabLemmas = 0;
  int grammarLemmas = 0;

  ConstructListModel({
    required List<OneConstructUse> uses,
  }) {
    updateConstructs(uses);
  }

  /// Given a list of new construct uses, update the map of construct
  /// IDs to ConstructUses and re-sort the list of ConstructUses
  void updateConstructs(List<OneConstructUse> newUses) {
    try {
      _updateUsesList(newUses);
      _updateConstructMap(newUses);
      _updateConstructList();
      _updateCategoriesToUses();
      _updateMetrics();
    } catch (err, s) {
      ErrorHandler.logError(e: "Failed to update analytics: $err", s: s);
    }
  }

  int _sortConstructs(ConstructUses a, ConstructUses b) {
    final comp = b.points.compareTo(a.points);
    if (comp != 0) return comp;
    return a.lemma.compareTo(b.lemma);
  }

  void _updateUsesList(List<OneConstructUse> newUses) {
    newUses.sort((a, b) => b.timeStamp.compareTo(a.timeStamp));
    _uses.insertAll(0, newUses);
    _uses = _uses.take(100).toList();
  }

  /// A map of lemmas to ConstructUses, each of which contains a lemma
  /// key = lemmma + constructType.string, value = ConstructUses
  void _updateConstructMap(final List<OneConstructUse> newUses) {
    for (final use in newUses) {
      final currentUses = _constructMap[use.identifier.string] ??
          ConstructUses(
            uses: [],
            constructType: use.constructType,
            lemma: use.lemma,
            category: use.category,
          );
      currentUses.uses.add(use);
      currentUses.setLastUsed(use.timeStamp);
      _constructMap[use.identifier.string] = currentUses;
    }

    final broadKeys = _constructMap.keys.where((key) => key.endsWith('other'));
    final replacedKeys = [];
    for (final broadKey in broadKeys) {
      final specificKeyPrefix = broadKey.split("-").first;
      final specificKey = _constructMap.keys.firstWhereOrNull(
        (key) =>
            key != broadKey &&
            key.startsWith(specificKeyPrefix) &&
            !key.endsWith('other'),
      );
      if (specificKey == null) continue;
      final broadConstructEntry = _constructMap[broadKey];
      final specificConstructEntry = _constructMap[specificKey];
      specificConstructEntry!.uses.addAll(broadConstructEntry!.uses);
      _constructMap[specificKey] = specificConstructEntry;
      replacedKeys.add(broadKey);
    }

    for (final key in replacedKeys) {
      _constructMap.remove(key);
    }
  }

  /// A list of ConstructUses, each of which contains a lemma and
  /// a list of uses, sorted by the number of uses
  void _updateConstructList() {
    // TODO check how expensive this is
    _constructList = _constructMap.values.toList();
    _constructList.sort(_sortConstructs);
  }

  void _updateCategoriesToUses() {
    _categoriesToUses = {};
    for (final ConstructUses use in constructList()) {
      final category = use.category;
      _categoriesToUses.putIfAbsent(category, () => []);
      _categoriesToUses[category]!.add(use);
    }
  }

  void _updateMetrics() {
    vocabLemmas = constructList(type: ConstructTypeEnum.vocab)
        .map((e) => e.lemma)
        .toSet()
        .length;

    grammarLemmas = constructList(type: ConstructTypeEnum.morph)
        .map((e) => e.lemma)
        .toSet()
        .length;

    prevXP = totalXP;
    totalXP = _constructList.fold<int>(
      0,
      (total, construct) => total + construct.points,
    );

    if (totalXP < 0) {
      totalXP = 0;
    }

    // Don't call .floor() if NaN or Infinity
    // https://pangea-chat.sentry.io/issues/6052871310
    final double levelCalculation = 1 + sqrt((1 + 8 * totalXP / 100) / 2);
    if (!levelCalculation.isNaN && levelCalculation.isFinite) {
      level = levelCalculation.floor();
    } else {
      level = 1;
      Sentry.addBreadcrumb(
        Breadcrumb(
          data: {
            "totalXP": totalXP,
            "prevXP": prevXP,
            "level": levelCalculation,
          },
        ),
      );
      ErrorHandler.logError(e: "Calculated level in Nan or Infinity");
    }
  }

  ConstructUses? getConstructUses(ConstructIdentifier identifier) {
    final partialKey = "${identifier.lemma}-${identifier.type.string}";

    if (_constructMap.containsKey(identifier.string)) {
      // try to get construct use entry with full ID key
      return _constructMap[identifier.string];
    } else if (identifier.category == "other") {
      // if the category passed to this function is "other", return the first
      // construct use entry that starts with the partial key
      return _constructMap.entries
          .firstWhereOrNull((entry) => entry.key.startsWith(partialKey))
          ?.value;
    } else {
      // if the category passed to this function is not "other", return the first
      // construct use entry that starts with the partial key and ends with "other"
      return _constructMap.entries
          .firstWhereOrNull(
            (entry) =>
                entry.key.startsWith(partialKey) && entry.key.endsWith("other"),
          )
          ?.value;
    }
  }

  List<ConstructUses> constructList({ConstructTypeEnum? type}) => _constructList
      .where(
        (constructUse) =>
            constructUse.points > 0 &&
            (type == null || constructUse.constructType == type),
      )
      .toList();

  Map<String, List<ConstructUses>> categoriesToUses({ConstructTypeEnum? type}) {
    if (type == null) return _categoriesToUses;
    final entries = _categoriesToUses.entries.toList();
    return Map.fromEntries(
      entries.map((entry) {
        return MapEntry(
          entry.key,
          entry.value.where((use) => use.constructType == type).toList(),
        );
      }).where((entry) => entry.value.isNotEmpty),
    );
  }
}
