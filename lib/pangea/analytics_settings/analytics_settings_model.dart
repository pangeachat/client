import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

class BlockedConstruct {
  final ConstructIdentifier constructId;
  final DateTime? timestamp;
  final ConstructSnapshot? snapshot;

  const BlockedConstruct({
    required this.constructId,
    this.timestamp,
    this.snapshot,
  });

  Map<String, dynamic> toJson() => {
    "construct_id": constructId.toJson(),
    "timestamp": timestamp?.millisecondsSinceEpoch,
    "snapshot": snapshot?.toJson(),
  };

  factory BlockedConstruct.fromJson(Map<String, dynamic> json) =>
      BlockedConstruct(
        constructId: ConstructIdentifier.fromJson(
          Map<String, dynamic>.from(json["construct_id"]),
        ),
        timestamp: json["timestamp"] != null
            ? DateTime.fromMillisecondsSinceEpoch(json["timestamp"])
            : null,
        snapshot: json["snapshot"] != null
            ? ConstructSnapshot.fromJson(
                Map<String, dynamic>.from(json["snapshot"]),
              )
            : null,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockedConstruct &&
          runtimeType == other.runtimeType &&
          constructId == other.constructId &&
          timestamp == other.timestamp &&
          snapshot == other.snapshot;

  @override
  int get hashCode => Object.hashAll([constructId, timestamp, snapshot]);
}

class ConstructSnapshot {
  final int points;

  const ConstructSnapshot({required this.points});

  Map<String, dynamic> toJson() => {"points": points};

  factory ConstructSnapshot.fromJson(Map<String, dynamic> json) =>
      ConstructSnapshot(points: json["points"]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstructSnapshot &&
          runtimeType == other.runtimeType &&
          points == other.points;

  @override
  int get hashCode => Object.hashAll([points]);
}

class AnalyticsSettingsModel {
  final Map<ConstructIdentifier, BlockedConstruct> blockedConstructs;

  const AnalyticsSettingsModel({required this.blockedConstructs});

  AnalyticsSettingsModel copyWith({
    Map<ConstructIdentifier, BlockedConstruct>? blockedConstructs,
  }) {
    return AnalyticsSettingsModel(
      blockedConstructs: blockedConstructs ?? this.blockedConstructs,
    );
  }

  factory AnalyticsSettingsModel.fromJson(Map<String, dynamic> json) {
    final Map<ConstructIdentifier, BlockedConstruct> blockedConstructs = {};

    final legacyEntry = json['blocked_constructs'];
    if (legacyEntry != null) {
      final constructIds = List.from(legacyEntry);
      for (final entry in constructIds) {
        final constructId = ConstructIdentifier.fromJson(entry);
        blockedConstructs[constructId] = BlockedConstruct(
          constructId: constructId,
        );
      }
    }

    final currentEntry = json['blocked_constructs_v2'];
    if (currentEntry != null) {
      final current = List.from(currentEntry);
      final parsed = Map.fromEntries(
        current.map((e) {
          final blocked = BlockedConstruct.fromJson(
            Map<String, dynamic>.from(e),
          );
          return MapEntry<ConstructIdentifier, BlockedConstruct>(
            blocked.constructId,
            blocked,
          );
        }),
      );
      blockedConstructs.addAll(parsed);
    }

    return AnalyticsSettingsModel(blockedConstructs: blockedConstructs);
  }

  Map<String, dynamic> toJson() {
    return {
      'blocked_constructs_v2': blockedConstructs.values
          .map((c) => c.toJson())
          .toList(),
    };
  }
}
