import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_word_diff.dart';
import 'package:fluffychat/routes/chat/events/tokens/stt_transcript_tokens.dart';

/// Compact sent-transcript edit annotation. Unchanged words remain plain,
/// replacements show the edited word in orange with its spoken source below,
/// and insertions show only the orange word.
class TranscriptDiffView extends StatelessWidget {
  const TranscriptDiffView({
    required this.originalAsrText,
    required this.transcription,
    required this.eventId,
    required this.onTokenSelected,
    required this.isTokenSelected,
    this.vocabLemmas,
    this.newTokensOverride,
    super.key,
  });

  final String originalAsrText;
  final SpeechToTextResponseModel transcription;
  final String eventId;
  final void Function(PangeaToken) onTokenSelected;
  final bool Function(PangeaToken) isTokenSelected;
  final Set<String>? vocabLemmas;
  final Set<PangeaTokenText>? newTokensOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = DefaultTextStyle.of(context).style;
    final sourceStyle = baseStyle.copyWith(
      fontSize: theme.textTheme.bodySmall?.fontSize,
      color:
          baseStyle.color?.withAlpha(160) ?? theme.colorScheme.onSurfaceVariant,
    );
    final currentText = transcription.transcript.text;
    final changes = _positionedChanges(originalAsrText, currentText);
    final deleted = changes
        .where((change) => change.currentStart == null)
        .map((change) => change.original)
        .whereType<String>()
        .toList();
    return Column(
      key: const Key('stt-inline-diff'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SttTranscriptTokens(
          eventId: eventId,
          model: transcription,
          style: baseStyle,
          onClick: onTokenSelected,
          isSelected: isTokenSelected,
          vocabLemmas: vocabLemmas,
          newTokensOverride: newTokensOverride,
          presentationForToken: (_, startIndex, endIndex) {
            final overlapping = changes.where(
              (change) =>
                  change.currentStart != null &&
                  change.currentStart! < endIndex &&
                  change.currentEnd! > startIndex,
            );
            if (overlapping.isEmpty) return null;
            final changed = overlapping.any((change) => change.changed);
            final source = overlapping
                .where(
                  (change) =>
                      change.changed &&
                      change.original != null &&
                      change.currentStart! >= startIndex &&
                      change.currentStart! < endIndex,
                )
                .map((change) => change.original)
                .firstOrNull;
            return (
              idleUnderlineColor: changed
                  ? AppConfig.warning
                  : AppConfig.success,
              secondaryText: source,
              secondaryStyle: source == null
                  ? null
                  : sourceStyle.copyWith(
                      decoration: TextDecoration.lineThrough,
                    ),
            );
          },
        ),
        if (deleted.isNotEmpty)
          Wrap(
            spacing: 4,
            children: [
              for (final original in deleted)
                Text(
                  original,
                  style: sourceStyle.copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

typedef _PositionedChange = ({
  String? original,
  bool changed,
  int? currentStart,
  int? currentEnd,
});

typedef _WordRange = ({int start, int end});

List<_PositionedChange> _positionedChanges(String original, String current) {
  final words = <_WordRange>[];
  var index = 0;
  int? start;
  for (final character in current.characters) {
    final whitespace = character.trim().isEmpty;
    if (!whitespace && start == null) start = index;
    if (whitespace && start != null) {
      words.add((start: start, end: index));
      start = null;
    }
    index++;
  }
  if (start != null) words.add((start: start, end: index));

  var currentWord = 0;
  return [
    for (final change in sttWordChanges(original, current))
      if (change.current == null)
        (
          original: change.original,
          changed: change.changed,
          currentStart: null,
          currentEnd: null,
        )
      else
        (
          original: change.original,
          changed: change.changed,
          currentStart: words[currentWord].start,
          currentEnd: words[currentWord++].end,
        ),
  ];
}

/// The pre-send editor's compact source reference: only replaced/deleted spoken
/// words are shown, never the full original sentence.
class ChangedOriginalWords extends StatelessWidget {
  const ChangedOriginalWords({
    required this.originalAsrText,
    required this.currentText,
    super.key,
  });

  final String originalAsrText;
  final String currentText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final originals = sttWordChanges(
      originalAsrText,
      currentText,
    ).map((change) => change.original).whereType<String>().toList();
    if (originals.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('stt-editor-original-changes'),
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        children: [
          for (final original in originals)
            Text(
              original,
              style: theme.textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
