import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/choreographer/igc/text_normalization_util.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'span_choice_type_enum.dart';
import 'span_data_type_enum.dart';

class SpanData {
  final String? message;
  final String? shortMessage;
  final List<SpanChoice>? choices;
  final int offset;
  final int length;
  final String fullText;
  final SpanDataType type;
  final Rule? rule;

  SpanData({
    required this.message,
    required this.shortMessage,
    required this.choices,
    required this.offset,
    required this.length,
    required this.fullText,
    required this.type,
    required this.rule,
  });

  SpanData copyWith({
    String? message,
    String? shortMessage,
    List<SpanChoice>? choices,
    int? offset,
    int? length,
    String? fullText,
    SpanDataType? type,
    Rule? rule,
  }) {
    return SpanData(
      message: message ?? this.message,
      shortMessage: shortMessage ?? this.shortMessage,
      choices: choices ?? this.choices,
      offset: offset ?? this.offset,
      length: length ?? this.length,
      fullText: fullText ?? this.fullText,
      type: type ?? this.type,
      rule: rule ?? this.rule,
    );
  }

  factory SpanData.fromJson(Map<String, dynamic> json) {
    final Iterable? choices = json['choices'] ?? json['replacements'];
    return SpanData(
      message: json['message'],
      shortMessage: json['shortMessage'] ?? json['short_message'],
      choices: choices
          ?.map<SpanChoice>(
            (e) => SpanChoice.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      offset: json['offset'] as int,
      length: json['length'] as int,
      fullText:
          json['sentence'] ?? json['full_text'] ?? json['fullText'] as String,
      type: SpanDataType.fromJson(json['type'] as Map<String, dynamic>),
      rule: json['rule'] != null
          ? Rule.fromJson(json['rule'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'offset': offset,
      'length': length,
      'full_text': fullText,
      'type': type.toJson(),
    };

    if (message != null) {
      data['message'] = message;
    }

    if (shortMessage != null) {
      data['short_message'] = shortMessage;
    }

    if (choices != null) {
      data['choices'] = List<dynamic>.from(choices!.map((x) => x.toJson()));
    }

    if (rule != null) {
      data['rule'] = rule!.toJson();
    }

    return data;
  }

  bool isOffsetInMatchSpan(int offset) =>
      offset >= this.offset && offset <= this.offset + length;

  SpanChoice? get bestChoice {
    return choices?.firstWhereOrNull((choice) => choice.isBestCorrection);
  }

  int get selectedChoiceIndex {
    if (choices == null) {
      return -1;
    }

    SpanChoice? mostRecent;
    for (int i = 0; i < choices!.length; i++) {
      final choice = choices![i];
      if (choice.timestamp != null &&
          (mostRecent == null ||
              choice.timestamp!.isAfter(mostRecent.timestamp!))) {
        mostRecent = choice;
      }
    }
    return mostRecent != null ? choices!.indexOf(mostRecent) : -1;
  }

  SpanChoice? get selectedChoice {
    final index = selectedChoiceIndex;
    if (index == -1) {
      return null;
    }
    return choices![index];
  }

  String get errorSpan =>
      fullText.characters.skip(offset).take(length).toString();

  bool isNormalizationError() {
    final correctChoice = choices
        ?.firstWhereOrNull((c) => c.isBestCorrection)
        ?.value;

    final l2Code =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    return correctChoice != null &&
        l2Code != null &&
        normalizeString(correctChoice, l2Code) ==
            normalizeString(errorSpan, l2Code);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SpanData) return false;
    if (other.message != message) return false;
    if (other.shortMessage != shortMessage) return false;
    if (other.offset != offset) return false;
    if (other.length != length) return false;
    if (other.fullText != fullText) return false;
    if (other.type != type) return false;
    if (other.rule != rule) return false;
    if (const ListEquality().equals(
          other.choices?.sorted((a, b) => b.value.compareTo(a.value)),
          choices?.sorted((a, b) => b.value.compareTo(a.value)),
        ) ==
        false) {
      return false;
    }
    return true;
  }

  @override
  int get hashCode {
    return message.hashCode ^
        shortMessage.hashCode ^
        Object.hashAll(
          (choices ?? [])
              .sorted((a, b) => b.value.compareTo(a.value))
              .map((choice) => choice.hashCode),
        ) ^
        offset.hashCode ^
        length.hashCode ^
        fullText.hashCode ^
        type.hashCode ^
        rule.hashCode;
  }
}

class SpanChoice {
  final String value;
  final SpanChoiceTypeEnum type;
  final bool selected;
  final String? feedback;
  final DateTime? timestamp;

  SpanChoice({
    required this.value,
    required this.type,
    this.feedback,
    this.selected = false,
    this.timestamp,
  });

  SpanChoice copyWith({
    String? value,
    SpanChoiceTypeEnum? type,
    String? feedback,
    bool? selected,
    DateTime? timestamp,
  }) {
    return SpanChoice(
      value: value ?? this.value,
      type: type ?? this.type,
      feedback: feedback ?? this.feedback,
      selected: selected ?? this.selected,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  factory SpanChoice.fromJson(Map<String, dynamic> json) {
    return SpanChoice(
      value: json['value'] as String,
      type: json['type'] != null
          ? SpanChoiceTypeEnum.values.firstWhereOrNull(
                  (element) => element.name == json['type'],
                ) ??
                SpanChoiceTypeEnum.bestCorrection
          : SpanChoiceTypeEnum.bestCorrection,
      feedback: json['feedback'],
      selected: json['selected'] ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {'value': value, 'type': type.name};

    if (selected) {
      data['selected'] = selected;
    }

    if (feedback != null) {
      data['feedback'] = feedback;
    }

    if (timestamp != null) {
      data['timestamp'] = timestamp!.toIso8601String();
    }

    return data;
  }

  String feedbackToDisplay(BuildContext context) {
    if (feedback == null) {
      return type.defaultFeedback(context);
    }
    return feedback!;
  }

  bool get isBestCorrection => type == SpanChoiceTypeEnum.bestCorrection;

  Color get color => type.color;

  // override == operator and hashcode
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SpanChoice &&
        other.value == value &&
        other.type.toString() == type.toString() &&
        other.selected == selected &&
        other.feedback == feedback &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return value.hashCode ^
        type.hashCode ^
        selected.hashCode ^
        feedback.hashCode ^
        timestamp.hashCode;
  }
}

class Rule {
  final String id;

  const Rule({required this.id});

  factory Rule.fromJson(Map<String, dynamic> json) =>
      Rule(id: json['id'] as String);

  Map<String, dynamic> toJson() => {'id': id};

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Rule) return false;
    return other.id == id;
  }

  @override
  int get hashCode {
    return id.hashCode;
  }
}

class SpanDataType {
  final SpanDataTypeEnum typeName;

  const SpanDataType({required this.typeName});

  factory SpanDataType.fromJson(Map<String, dynamic> json) {
    final String? type =
        json['typeName'] ?? json['type'] ?? json['type_name'] as String?;
    return SpanDataType(
      typeName: type != null
          ? SpanDataTypeEnum.values.firstWhereOrNull(
                  (element) => element.name == type,
                ) ??
                SpanDataTypeEnum.correction
          : SpanDataTypeEnum.correction,
    );
  }

  Map<String, dynamic> toJson() => {'type_name': typeName.name};

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SpanDataType) return false;
    return other.typeName == typeName;
  }

  @override
  int get hashCode {
    return typeName.hashCode;
  }
}
