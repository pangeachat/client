import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

enum ConstructTypeEnum {
  /// for vocabulary words
  vocab,

  /// for morphs, actually called "Grammar" in the UI... :P
  morph;

  String get string {
    switch (this) {
      case ConstructTypeEnum.vocab:
        return 'vocab';
      case ConstructTypeEnum.morph:
        return 'morph';
    }
  }

  String sheetname(BuildContext context) {
    final l10n = L10n.of(context);
    switch (this) {
      case ConstructTypeEnum.vocab:
        return l10n.vocab;
      case ConstructTypeEnum.morph:
        return l10n.grammar;
    }
  }

  ProgressIndicatorEnum get indicator {
    switch (this) {
      case ConstructTypeEnum.morph:
        return ProgressIndicatorEnum.morphsUsed;
      case ConstructTypeEnum.vocab:
        return ProgressIndicatorEnum.wordsUsed;
    }
  }

  String practiceButtonText(BuildContext context) {
    final l10n = L10n.of(context);
    switch (this) {
      case ConstructTypeEnum.vocab:
        return l10n.practiceVocab;
      case ConstructTypeEnum.morph:
        return l10n.practiceGrammar;
    }
  }

  static ConstructTypeEnum fromString(String? string) {
    switch (string) {
      case 'v':
      case 'vocab':
        return ConstructTypeEnum.vocab;
      case 'm':
      case 'morph':
        return ConstructTypeEnum.morph;
      default:
        debugger(when: kDebugMode);
        return ConstructTypeEnum.vocab;
    }
  }

  /// The canonical panel-token spelling: `vocab` / `grammar` (never the legacy
  /// `morph`). One vocabulary across the token grammar — see
  /// routing.instructions.md and google-analytics.instructions.md.
  String get canonicalTokenParam =>
      this == ConstructTypeEnum.morph ? 'grammar' : 'vocab';

  /// Parse a panel-token construct spelling: the canonical `grammar`/`vocab`,
  /// tolerating the legacy `morph` as an inbound-only alias.
  static ConstructTypeEnum fromTokenParam(String? param) =>
      (param == 'grammar' || param == 'morph')
      ? ConstructTypeEnum.morph
      : ConstructTypeEnum.vocab;
}
