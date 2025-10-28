import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import '../constants/choreo_constants.dart';

class ITStep {
  final List<Continuance> continuances;
  final int? chosen;
  final String? customInput;
  final bool showAlternativeTranslationOption = false;

  ITStep(
    this.continuances, {
    this.chosen,
    this.customInput,
  }) {
    if (chosen == null && customInput == null) {
      throw Exception("ITStep must have either chosen or customInput");
    }
    if (chosen != null && customInput != null) {
      throw Exception("ITStep must have only chosen or customInput");
    }
  }

  Continuance? get chosenContinuance {
    if (chosen == null) return null;
    return continuances[chosen!];
  }

  String choiceFeedback(BuildContext context) {
    if (continuances.length == 1) return '';
    return chosenContinuance?.feedbackText(context) ?? "";
  }

  bool get isCorrect =>
      chosenContinuance != null &&
      (chosenContinuance!.level == ChoreoConstants.levelThresholdForGreen ||
          chosenContinuance!.gold);

  bool get isYellow =>
      chosenContinuance != null &&
      chosenContinuance!.level == ChoreoConstants.levelThresholdForYellow;

  bool get isWrong {
    return chosenContinuance != null &&
        chosenContinuance!.level == ChoreoConstants.levelThresholdForRed;
  }

  bool get isCustom => chosenContinuance == null;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['continuances'] = continuances.map((e) => e.toJson(true)).toList();
    data['chosen'] = chosen;
    data['custom_input'] = customInput;
    return data;
  }

  factory ITStep.fromJson(Map<String, dynamic> json) {
    final List<Continuance> continuances = <Continuance>[];
    for (final Map<String, dynamic> continuance in json['continuances']) {
      continuances.add(Continuance.fromJson(continuance));
    }
    return ITStep(
      continuances,
      chosen: json['chosen'],
      customInput: json['custom_input'],
    );
  }
}

class Continuance {
  final double probability;
  final int level;
  final String text;

  final String description;
  final int? indexSavedByServer;
  final bool wasClicked;
  final bool inDictionary;
  final bool hasInfo;
  final bool gold;

  const Continuance({
    required this.probability,
    required this.level,
    required this.text,
    required this.description,
    required this.indexSavedByServer,
    required this.wasClicked,
    required this.inDictionary,
    required this.hasInfo,
    required this.gold,
  });

  factory Continuance.fromJson(Map<String, dynamic> json) {
    return Continuance(
      probability: json['probability'].toDouble(),
      level: json['level'],
      text: json['text'],
      description: json['description'] ?? "",
      indexSavedByServer: json["index"],
      inDictionary: json['in_dictionary'] ?? true,
      wasClicked: json['clkd'] ?? false,
      hasInfo: json['has_info'] ?? false,
      gold: json['gold'] ?? false,
    );
  }

  Map<String, dynamic> toJson([bool condensed = false]) {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['probability'] = probability;
    data['level'] = level;
    data['text'] = text;
    data['clkd'] = wasClicked;
    // data[ModelKey.tokens] = tokens.map((e) => e.toJson()).toList();

    if (!condensed) {
      data['description'] = description;
      data['in_dictionary'] = inDictionary;
      data['has_info'] = hasInfo;
      data["index"] = indexSavedByServer;
      data['gold'] = gold;
    }
    return data;
  }

  Continuance copyWith({
    double? probability,
    int? level,
    String? text,
    String? description,
    int? indexSavedByServer,
    bool? wasClicked,
    bool? inDictionary,
    bool? hasInfo,
    bool? gold,
  }) {
    return Continuance(
      probability: probability ?? this.probability,
      level: level ?? this.level,
      text: text ?? this.text,
      description: description ?? this.description,
      indexSavedByServer: indexSavedByServer ?? this.indexSavedByServer,
      wasClicked: wasClicked ?? this.wasClicked,
      inDictionary: inDictionary ?? this.inDictionary,
      hasInfo: hasInfo ?? this.hasInfo,
      gold: gold ?? this.gold,
    );
  }

  Color? get color {
    if (!wasClicked) return null;
    switch (level) {
      case ChoreoConstants.levelThresholdForGreen:
        return ChoreoConstants.green;
      case ChoreoConstants.levelThresholdForYellow:
        return ChoreoConstants.yellow;
      case ChoreoConstants.levelThresholdForRed:
        return ChoreoConstants.red;
      default:
        return null;
    }
  }

  String? feedbackText(BuildContext context) {
    final L10n l10n = L10n.of(context);
    switch (level) {
      case ChoreoConstants.levelThresholdForGreen:
        return l10n.greenFeedback;
      case ChoreoConstants.levelThresholdForYellow:
        return l10n.yellowFeedback;
      case ChoreoConstants.levelThresholdForRed:
        return l10n.redFeedback;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Continuance &&
          runtimeType == other.runtimeType &&
          probability == other.probability &&
          level == other.level &&
          text == other.text &&
          description == other.description &&
          indexSavedByServer == other.indexSavedByServer &&
          wasClicked == other.wasClicked &&
          inDictionary == other.inDictionary &&
          hasInfo == other.hasInfo &&
          gold == other.gold;

  @override
  int get hashCode =>
      probability.hashCode ^
      level.hashCode ^
      text.hashCode ^
      description.hashCode ^
      indexSavedByServer.hashCode ^
      wasClicked.hashCode ^
      inDictionary.hashCode ^
      hasInfo.hashCode ^
      gold.hashCode;
}
