import 'package:flutter/painting.dart';

import 'package:characters/characters.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/stt_word_diff.dart';
import 'package:fluffychat/routes/chat/events/tokens/highlight_style.dart';

/// Colors the word-level diff of [edited] against [original] into ordered inline
/// spans, per the D10 contract: the diff signal is an UNDERLINE (default) or a
/// BACKFILL (when [fill]) — NOT the text color, which stays the inherited
/// default. CHANGED runs use [changedColor] (orange), UNCHANGED runs use
/// [unchangedColor] (green) — the SAME [highlightTextStyle] mechanism, only
/// the color differs. Each run merges onto [baseStyle]. Pure (no [BuildContext]);
/// concatenating the spans' text reconstructs [edited] verbatim. Shared by the
/// live editable field (`EditableTranscriptController.buildTextSpan`) and the
/// read-only [TranscriptDiffView].
///
/// The two colors arrive from the caller rather than from `AppConfig` directly,
/// so this stays pure while they stay theme-aware: the light theme's pale
/// surfaces left the bright constants at 1.94:1 and 3.01:1, under the 3:1 an
/// underline carrying the diff signal needs (#8764).
///
/// Colour is not the only difference between the two runs: unchanged runs are
/// DASHED and changed runs stay SOLID, so the diff survives with colour removed
/// (SC 1.4.1). Changed keeps the solid rule because the learner's own edits are
/// the mark that should dominate.
List<TextSpan> sttDiffTextSpans(
  String original,
  String edited, {
  TextStyle? baseStyle,
  bool fill = false,
  required Color changedColor,
  required Color unchangedColor,
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
                    color: run.changed ? changedColor : unchangedColor,
                    fill: fill,
                    style: run.changed
                        ? TextDecorationStyle.solid
                        : sttUnchangedUnderlineStyle,
                  ),
                ),
        ),
  ];
}

/// How an UNCHANGED run's underline is drawn, against the changed runs' solid
/// rule — the non-colour half of the diff signal (SC 1.4.1, #8764).
const TextDecorationStyle sttUnchangedUnderlineStyle =
    TextDecorationStyle.dashed;

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
