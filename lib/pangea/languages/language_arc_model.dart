import 'package:fluffychat/pangea/languages/language_model.dart';

class LanguageArc {
  final LanguageModel l1;
  final LanguageModel l2;

  LanguageArc({
    required this.l1,
    required this.l2,
  });

  factory LanguageArc.fromJson(Map<String, dynamic> json) {
    return LanguageArc(
      l1: LanguageModel.fromJson(json['l1'] as Map<String, dynamic>),
      l2: LanguageModel.fromJson(json['l2'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'l1': l1.toJson(),
      'l2': l2.toJson(),
    };
  }

  @override
  int get hashCode => l1.hashCode ^ l2.hashCode;

  @override
  bool operator ==(Object other) {
    return other is LanguageArc && other.l1 == l1 && other.l2 == l2;
  }
}
