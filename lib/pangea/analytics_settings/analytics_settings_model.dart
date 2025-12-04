class AnalyticsSettingsModel {
  final Set<String> blockedLemmas;

  const AnalyticsSettingsModel({
    required this.blockedLemmas,
  });

  AnalyticsSettingsModel copyWith({
    Set<String>? blockedLemmas,
  }) {
    return AnalyticsSettingsModel(
      blockedLemmas: blockedLemmas ?? this.blockedLemmas,
    );
  }

  factory AnalyticsSettingsModel.fromJson(Map<String, dynamic> json) {
    final blockedLemmas = <String>{};
    if (json['blocked_lemmas'] != null) {
      final lemmas = json['blocked_lemmas'] as List<dynamic>;
      for (final lemma in lemmas) {
        blockedLemmas.add(lemma as String);
      }
    }
    return AnalyticsSettingsModel(
      blockedLemmas: blockedLemmas,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blocked_lemmas': blockedLemmas.toList(),
    };
  }
}
