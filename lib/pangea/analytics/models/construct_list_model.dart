import 'dart:math';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics/constants/analytics_constants.dart';
import 'package:fluffychat/pangea/analytics/enums/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics/models/construct_identifier.dart';
import 'package:fluffychat/pangea/analytics/models/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics/models/constructs_model.dart';
import 'package:fluffychat/pangea/analytics/utils/get_grammar_copy.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// A wrapper around a list of [OneConstructUse]s, used to simplify
/// the process of filtering / sorting / displaying the events.
class ConstructListModel {
  void dispose() {
    _constructMap = {};
    _constructList = [];
    prevXP = 0;
    totalXP = 0;
    level = 0;
    _uses.clear();
  }

  final List<OneConstructUse> _uses = [];
  List<OneConstructUse> get uses => _uses;
  List<OneConstructUse> get truncatedUses => _uses.take(100).toList();

  /// A map of lemmas to ConstructUses, each of which contains a lemma
  /// key = lemma + constructType.string, value = ConstructUses
  Map<String, ConstructUses> _constructMap = {};

  /// Storing this to avoid re-running the sort operation each time this needs to
  /// be accessed. It contains the same information as _constructMap, but sorted.
  List<ConstructUses> _constructList = [];

  /// A map of categories to lists of ConstructUses
  Map<String, List<ConstructUses>> _categoriesToUses = {};

  /// A list of unique vocab lemmas
  List<String> vocabLemmasList = [];

  /// A list of unique grammar lemmas
  List<String> grammarLemmasList = [];

  /// Analytics data consumed by widgets. Updated each time new analytics come in.
  int prevXP = 0;
  int totalXP = 0;
  int level = 0;

  ConstructListModel({
    required List<OneConstructUse> uses,
  }) {
    updateConstructs(uses);
  }

  int get totalLemmas => vocabLemmasList.length + grammarLemmasList.length;
  int get vocabLemmas => vocabLemmasList.length;
  int get grammarLemmas => grammarLemmasList.length;
  List<String> get lemmasList => vocabLemmasList + grammarLemmasList;

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
      ErrorHandler.logError(
        e: "Failed to update analytics: $err",
        s: s,
        data: {
          "newUses": newUses.map((e) => e.toJson()),
        },
      );
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
    vocabLemmasList = constructList(type: ConstructTypeEnum.vocab)
        .map((e) => e.lemma)
        .toSet()
        .toList();

    grammarLemmasList = constructList(type: ConstructTypeEnum.morph)
        .map((e) => e.lemma)
        .toSet()
        .toList();

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
      ErrorHandler.logError(
        e: "Calculated level in Nan or Infinity",
        data: {
          "totalXP": totalXP,
          "prevXP": prevXP,
          "level": levelCalculation,
        },
      );
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

  List<ConstructUses> getConstructUsesByLemma(String lemma) {
    return _constructList.where((constructUse) {
      return constructUse.lemma == lemma;
    }).toList();
  }

  List<ConstructUses> constructList({ConstructTypeEnum? type}) => _constructList
      .where(
        (constructUse) => type == null || constructUse.constructType == type,
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

  // uses where points < AnalyticConstants.xpForGreens
  List<ConstructUses> get seeds => _constructList
      .where(
        (use) => use.points < AnalyticsConstants.xpForGreens,
      )
      .toList();

  List<ConstructUses> get greens => _constructList
      .where(
        (use) =>
            use.points >= AnalyticsConstants.xpForGreens &&
            use.points < AnalyticsConstants.xpForFlower,
      )
      .toList();

  List<ConstructUses> get flowers => _constructList
      .where(
        (use) => use.points >= AnalyticsConstants.xpForFlower,
      )
      .toList();
  // Not storing this for now to reduce memory load
  // It's only used by downloads, so doesn't need to be accessible on the fly
  Map<String, List<ConstructUses>> lemmasToUses({
    ConstructTypeEnum? type,
  }) {
    final Map<String, List<ConstructUses>> lemmasToUses = {};
    final constructs = constructList(type: type);
    for (final ConstructUses use in constructs) {
      final lemma = use.lemma;
      lemmasToUses.putIfAbsent(lemma, () => []);
      lemmasToUses[lemma]!.add(use);
    }
    return lemmasToUses;
  }
}

class LemmasToUsesWrapper {
  final Map<String, List<ConstructUses>> lemmasToUses;

  LemmasToUsesWrapper(this.lemmasToUses);

  Map<String, List<OneConstructUse>> lemmasToFilteredUses(
    bool Function(OneConstructUse) filter,
  ) {
    final Map<String, List<OneConstructUse>> lemmasToOneConstructUses = {};
    for (final entry in lemmasToUses.entries) {
      final lemma = entry.key;
      final uses = entry.value;
      lemmasToOneConstructUses[lemma] =
          uses.expand((use) => use.uses).toList().where(filter).toList();
    }
    return lemmasToOneConstructUses;
  }

  LemmasOverUnderList lemmasByPercent({
    required bool Function(OneConstructUse) filter,
    required double percent,
    required BuildContext context,
  }) {
    final List<String> correctUseLemmas = [];
    final List<String> incorrectUseLemmas = [];

    final uses = lemmasToFilteredUses(filter);
    for (final entry in uses.entries) {
      if (entry.value.isEmpty) continue;
      final List<OneConstructUse> correctUses = [];
      final List<OneConstructUse> incorrectUses = [];

      final lemma = getGrammarCopy(
            category: entry.value.first.category,
            lemma: entry.key,
            context: context,
          ) ??
          entry.key;
      final uses = entry.value.toList();

      for (final use in uses) {
        use.pointValue > 0 ? correctUses.add(use) : incorrectUses.add(use);
      }

      final totalUses = correctUses.length + incorrectUses.length;
      final percent = totalUses == 0 ? 0 : correctUses.length / totalUses;

      percent > 0.8
          ? correctUseLemmas.add(lemma)
          : incorrectUseLemmas.add(lemma);
    }

    return LemmasOverUnderList(
      over: correctUseLemmas,
      under: incorrectUseLemmas,
    );
  }

  /// Return an object containing two lists, one of lemmas with
  /// any correct uses and one of lemmas no correct uses
  LemmasOverUnderList lemmasByCorrectUse({
    String Function(ConstructUses)? getCopy,
  }) {
    final List<String> correctLemmas = [];
    final List<String> incorrectLemmas = [];
    for (final entry in lemmasToUses.entries) {
      final lemma = entry.key;
      final constructUses = entry.value;
      final copy = getCopy?.call(constructUses.first) ?? lemma;
      if (constructUses.any((use) => use.hasCorrectUse)) {
        correctLemmas.add(copy);
      } else {
        incorrectLemmas.add(copy);
      }
    }
    return LemmasOverUnderList(over: correctLemmas, under: incorrectLemmas);
  }

  int totalXP(String lemma) {
    final uses = lemmasToUses[lemma];
    if (uses == null) return 0;
    if (uses.length == 1) return uses.first.points;
    return lemmasToUses[lemma]!.fold<int>(
      0,
      (total, use) => total + use.points,
    );
  }

  List<String> thresholdedLemmas({
    required int start,
    int? end,
    String Function(ConstructUses)? getCopy,
  }) {
    final filteredList = lemmasToUses.entries.where((entry) {
      final xp = totalXP(entry.key);
      return xp >= start && (end == null || xp <= end);
    });
    return filteredList
        .map((entry) => getCopy?.call(entry.value.first) ?? entry.key)
        .toList();
  }
}

class LemmasOverUnderList {
  final List<String> over;
  final List<String> under;

  LemmasOverUnderList({
    required this.over,
    required this.under,
  });
}
