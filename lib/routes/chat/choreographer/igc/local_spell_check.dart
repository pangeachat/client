import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:characters/characters.dart';

import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';

/// Surface corrections read from the device's own spell checker, so a
/// misspelling can be resolved without waiting for the server.
/// See writing-assistance.instructions.md, "Local surface corrections".
abstract final class LocalSpellCheck {
  /// Overridable so tests can stand in for the platform channel.
  @visibleForTesting
  static SpellCheckService service = DefaultSpellCheckService();

  /// Whether a device spell checker is reachable at all. Flutter implements
  /// the spell check channel on Android and iOS only, so everywhere else the
  /// local pass is skipped and writing assistance stays server-only.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// The misspellings the device reports in [text] for [locale].
  ///
  /// Empty whenever the local pass cannot contribute — no device checker, no
  /// dictionary for the language, or a failed lookup. The caller cannot tell
  /// those apart and does not need to: each one falls back to the server
  /// alone, which is what writing assistance did before this existed.
  static Future<List<SpanData>> spans(String text, Locale locale) async {
    if (!isSupported || text.isEmpty) return const [];

    try {
      final suggestions = await service.fetchSpellCheckSuggestions(
        locale,
        text,
      );
      if (suggestions == null) return const [];
      return localSpansToSpanData(suggestions, text);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}

/// Converts the platform's misspelling reports into the same [SpanData] shape
/// the server returns, typed as [ReplacementTypeEnum.spell].
///
/// A report with no replacements is dropped: a match the learner cannot act
/// on is worse than no match, since it highlights a word while offering
/// nothing to tap.
///
/// The platform counts in UTF-16 code units and [SpanData] counts in
/// grapheme clusters, so every offset is converted. Skipping this puts every
/// span after an emoji or a combining mark on the wrong word.
List<SpanData> localSpansToSpanData(
  List<SuggestionSpan> suggestions,
  String text,
) {
  final spans = <SpanData>[];

  for (final suggestion in suggestions) {
    if (suggestion.suggestions.isEmpty) continue;

    final range = suggestion.range;
    if (range.start < 0 ||
        range.end > text.length ||
        range.start >= range.end) {
      continue;
    }

    spans.add(
      SpanData(
        message: null,
        shortMessage: null,
        choices: suggestion.suggestions
            .map(
              (value) =>
                  SpanChoice(value: value, type: SpanChoiceTypeEnum.suggestion),
            )
            .toList(),
        offset: text.substring(0, range.start).characters.length,
        length: text.substring(range.start, range.end).characters.length,
        fullText: text,
        type: ReplacementTypeEnum.spell,
        rule: null,
      ),
    );
  }

  return spans;
}
