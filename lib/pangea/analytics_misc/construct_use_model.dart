import 'dart:math';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_misc/analytics_constants.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';

/// One lemma and a list of construct uses for that lemma
class ConstructUses {
  final List<OneConstructUse> _uses;
  final ConstructTypeEnum constructType;
  final String lemma;
  String? _category;
  DateTime? _lastUsed;

  ConstructUses({
    required List<OneConstructUse> uses,
    required this.constructType,
    required this.lemma,
    required category,
  })  : _category = category,
        _uses = uses;

  // Total points for all uses of this lemma
  int get points {
    return min(
      _uses.fold<int>(
        0,
        (total, use) => total + use.xp,
      ),
      AnalyticsConstants.xpForFlower,
    );
  }

  DateTime? get lastUsed {
    if (_lastUsed != null) return _lastUsed;
    final lastUse = _uses.fold<DateTime?>(null, (DateTime? last, use) {
      if (last == null) return use.timeStamp;
      return use.timeStamp.isAfter(last) ? use.timeStamp : last;
    });
    return _lastUsed = lastUse;
  }

  void setLastUsed(DateTime time) {
    if (_lastUsed == null || time.isAfter(_lastUsed!)) {
      _lastUsed = time;
    }
  }

  String get category {
    if (_category == null || _category!.isEmpty) return "other";
    return _category!.toLowerCase();
  }

  bool get hasCorrectUse => _uses.any((use) => use.xp > 0);
  bool get hasIncorrectUse => _uses.any((use) => use.xp < 0);

  ConstructIdentifier get id => ConstructIdentifier(
        lemma: lemma,
        type: constructType,
        category: category,
      );

  Map<String, dynamic> toJson() {
    final json = {
      'construct_id': id.toJson(),
      'xp': points,
      'last_used': lastUsed?.toIso8601String(),
      'uses': _uses.map((e) => e.toJson()).toList(),
    };
    return json;
  }

  factory ConstructUses.fromJson(Map<String, dynamic> json) {
    final constructId = ConstructIdentifier.fromJson(
      Map<String, dynamic>.from(json['construct_id']),
    );

    List<dynamic> usesJson = [];
    if (json['uses'] is List) {
      usesJson = List<dynamic>.from(json['uses']);
    }

    final uses = usesJson
        .map((e) => OneConstructUse.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return ConstructUses(
      uses: uses,
      constructType: constructId.type,
      lemma: constructId.lemma,
      category: constructId.category,
    );
  }

  /// Get the lemma category, based on points
  ConstructLevelEnum get lemmaCategory {
    if (points < AnalyticsConstants.xpForGreens) {
      return ConstructLevelEnum.seeds;
    } else if (points >= AnalyticsConstants.xpForFlower) {
      return ConstructLevelEnum.flowers;
    }
    return ConstructLevelEnum.greens;
  }

  String get xpEmoji {
    if (points < 30) {
      // bean emoji
      return AnalyticsConstants.emojiForSeed;
    } else if (points < 100) {
      // sprout emoji
      return AnalyticsConstants.emojiForGreen;
    } else {
      // flower emoji
      return AnalyticsConstants.emojiForFlower;
    }
  }

  ConstructLevelEnum get constructLevel => switch (points) {
        < AnalyticsConstants.xpForGreens => ConstructLevelEnum.seeds,
        < AnalyticsConstants.xpForFlower => ConstructLevelEnum.greens,
        _ => ConstructLevelEnum.flowers,
      };

  List<String> get forms =>
      _uses.map((e) => e.form).whereType<String>().toSet().toList();

  DateTime? lastUseByTypes(List<ConstructUseTypeEnum> types) =>
      _uses.firstWhereOrNull((u) => types.contains(u.useType))?.timeStamp;

  void addUse(OneConstructUse use) => _uses.add(use);

  void merge(ConstructUses other) {
    if (other.lemma.toLowerCase() != lemma.toLowerCase() ||
        other.constructType != constructType) {
      throw ArgumentError(
        'Cannot merge ConstructUses with different lemmas or types',
      );
    }

    _uses.addAll(other._uses);
    if (other.lastUsed != null) {
      setLastUsed(other.lastUsed!);
    }

    if (category == 'other' && other.category != 'other') {
      _category = other.category;
    }
  }

  ConstructUses copyWith({
    List<OneConstructUse>? uses,
    ConstructTypeEnum? constructType,
    String? lemma,
    String? category,
  }) {
    return ConstructUses(
      uses: uses ?? _uses,
      constructType: constructType ?? this.constructType,
      lemma: lemma ?? this.lemma,
      category: category ?? _category,
    );
  }
}
