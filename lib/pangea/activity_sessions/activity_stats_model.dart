import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityStats {
  final int vocab;
  final int grammar;
  final int xp;

  const ActivityStats({
    required this.vocab,
    required this.grammar,
    required this.xp,
  });

  static ActivityStats current() {
    final analytics =
        MatrixState.pangeaController.getAnalytics.constructListModel;
    return ActivityStats(
      vocab: analytics.numConstructs(ConstructTypeEnum.vocab),
      grammar: analytics.numConstructs(ConstructTypeEnum.morph),
      xp: analytics.totalXP,
    );
  }

  factory ActivityStats.fromJson(Map<String, dynamic> json) {
    return ActivityStats(
      vocab: json['vocab'] as int,
      grammar: json['grammar'] as int,
      xp: json['xp'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vocab': vocab,
      'grammar': grammar,
      'xp': xp,
    };
  }

  ActivityStats operator -(ActivityStats other) {
    return ActivityStats(
      vocab: vocab - other.vocab,
      grammar: grammar - other.grammar,
      xp: xp - other.xp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActivityStats &&
        other.vocab == vocab &&
        other.grammar == grammar &&
        other.xp == xp;
  }

  @override
  int get hashCode => vocab.hashCode ^ grammar.hashCode ^ xp.hashCode;
}
