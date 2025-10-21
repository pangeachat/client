import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/learning_settings/enums/l2_support_enum.dart';
import 'package:fluffychat/pangea/learning_settings/utils/p_language_store.dart';

class LanguageModel {
  final String langCode;
  final String displayName;
  final String script;
  final L2SupportEnum l2Support;
  final TextDirection? _textDirection;

  LanguageModel({
    required this.langCode,
    required this.displayName,
    this.script = LanguageKeys.unknownLanguage,
    this.l2Support = L2SupportEnum.na,
    TextDirection? textDirection,
  }) : _textDirection = textDirection;

  factory LanguageModel.fromJson(json) {
    final String code = json['language_code'] ??
        codeFromNameOrCode(
          json['language_name'],
          json['language_flag'],
        );

    return LanguageModel(
      langCode: code,
      displayName: json['language_name'],
      l2Support: json['l2_support'] != null
          ? L2SupportEnum.na.fromStorageString(json['l2_support'])
          : L2SupportEnum.na,
      script: json['script'] ?? LanguageKeys.unknownLanguage,
      textDirection: json['text_direction'] != null
          ? TextDirection.values.firstWhereOrNull(
              (e) => e.name == json['text_direction'],
            )
          : null,
    );
  }

  toJson() => {
        'language_code': langCode,
        'language_name': displayName,
        'script': script,
        'l2_support': l2Support.storageString,
        'text_direction': textDirection.name,
      };

  bool get l2 => l2Support != L2SupportEnum.na;

  // Discuss with Jordan - adding langCode field to language objects as separate from displayName
  static String codeFromNameOrCode(String codeOrName, [String? url]) {
    if (codeOrName.isEmpty) return LanguageKeys.unknownLanguage;
    if (codeOrName == LanguageKeys.unknownLanguage) return codeOrName;

    if (url == null) return LanguageKeys.unknownLanguage;

    final List<String> split = url.split('/');
    return split.last.split('.').first;
  }

  //PTODO - add flag for unknown
  static LanguageModel get unknown => LanguageModel(
        langCode: LanguageKeys.unknownLanguage,
        displayName: "Unknown",
      );

  String? getDisplayName(BuildContext context) {
    return displayName;
  }

  String get langCodeShort => langCode.split('-').first;

  TextDirection get _defaultTextDirection {
    return PLanguageStore.rtlLanguageCodes.contains(langCodeShort)
        ? TextDirection.rtl
        : TextDirection.ltr;
  }

  TextDirection get textDirection {
    return _textDirection ?? _defaultTextDirection;
  }

  @override
  bool operator ==(Object other) {
    if (other is LanguageModel) {
      return langCode == other.langCode;
    }
    return false;
  }

  @override
  int get hashCode => langCode.hashCode;
}

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
}
