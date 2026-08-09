import 'package:flutter/painting.dart';

import 'package:characters/characters.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_word_diff.dart';
import 'package:fluffychat/routes/chat/events/tokens/highlight_style.dart';

/// Colors the word-level diff of [edited] against [original] into ordered inline
/// spans, per the D10 contract: the diff signal is an UNDERLINE (default) or a
/// BACKFILL (when [fill]) — NOT the text color, which stays the inherited
/// default. CHANGED runs use [AppConfig.warning] (orange), UNCHANGED runs use
/// [AppConfig.success] (green) — the SAME [highlightTextStyle] mechanism, only
/// the color differs. Each run merges onto [baseStyle]. Pure (no [BuildContext]);
/// concatenating the spans' text reconstructs [edited] verbatim. Shared by the
/// live editable field (`EditableTranscriptController.buildTextSpan`) and the
/// read-only [TranscriptDiffView].
List<TextSpan> sttDiffTextSpans(
  String original,
  String edited, {
  TextStyle? baseStyle,
  bool fill = false,
}) {
  final base = baseStyle ?? const TextStyle();
  return [
    for (final run in sttWordDiff(original, edited))
      for (final part in _splitWordsAndWhitespace(run.text))
        TextSpan(
          text: part.text,
          style: part.isWhitespace
              ? base
              : base.merge(
                  highlightTextStyle(
                    color: run.changed ? AppConfig.warning : AppConfig.success,
                    fill: fill,
                  ),
                ),
        ),
  ];
}

typedef _SpanPart = ({String text, bool isWhitespace});

List<_SpanPart> _splitWordsAndWhitespace(String text) {
  final parts = <_SpanPart>[];
  final buffer = StringBuffer();
  bool? whitespace;
  for (final character in text.characters) {
    final nextWhitespace = character.trim().isEmpty;
    if (whitespace != null && whitespace != nextWhitespace) {
      parts.add((text: buffer.toString(), isWhitespace: whitespace));
      buffer.clear();
    }
    whitespace = nextWhitespace;
    buffer.write(character);
  }
  if (whitespace != null) {
    parts.add((text: buffer.toString(), isWhitespace: whitespace));
  }
  return parts;
}
