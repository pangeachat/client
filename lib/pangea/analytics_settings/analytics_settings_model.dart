import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

class AnalyticsSettingsModel {
  final Set<ConstructIdentifier> blockedConstructs;

  const AnalyticsSettingsModel({
    required this.blockedConstructs,
  });

  AnalyticsSettingsModel copyWith({
    Set<ConstructIdentifier>? blockedConstructs,
  }) {
    return AnalyticsSettingsModel(
      blockedConstructs: blockedConstructs ?? this.blockedConstructs,
    );
  }

  factory AnalyticsSettingsModel.fromJson(Map<String, dynamic> json) {
    final blockedConstructs = <ConstructIdentifier>{};
    if (json['blocked_constructs'] != null) {
      final lemmas = json['blocked_constructs'] as List<dynamic>;
      for (final lemma in lemmas) {
        blockedConstructs.add(ConstructIdentifier.fromJson(lemma));
      }
    }
    return AnalyticsSettingsModel(
      blockedConstructs: blockedConstructs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blocked_constructs': blockedConstructs.map((c) => c.toJson()).toList(),
    };
  }
}
