import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/editable_transcript.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/transcript_diff_view.dart';
import 'package:fluffychat/routes/chat/recording_view_model.dart';

class RecordingInputRow extends StatelessWidget {
  final RecordingViewModelState state;
  final VoiceMessageSend onSend;
  const RecordingInputRow({
    required this.state,
    required this.onSend,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const maxDecibalWidth = 36.0;
    final time =
        '${state.duration.inMinutes.toString().padLeft(2, '0')}:${(state.duration.inSeconds % 60).toString().padLeft(2, '0')}';
    final controlsRow = Row(
      children: [
        IconButton(
          tooltip: L10n.of(context).cancel,
          icon: const Icon(Icons.delete_outlined),
          color: theme.colorScheme.error,
          // #Pangea
          // onPressed: state.cancel,
          onPressed: state.isSending ? null : state.cancel,
          // Pangea#
        ),
        // #Pangea
        // The pilot streaming socket has no resumable pause, so the pause/resume
        // control is only shown on the batch path (D6).
        if (!state.isStreaming)
          // Pangea#
          if (state.isPaused)
            IconButton(
              tooltip: L10n.of(context).resume,
              icon: const Icon(Icons.play_circle_outline_outlined),
              // #Pangea
              // onPressed: state.resume,
              onPressed: state.isSending ? null : state.resume,
              // Pangea#
            )
          else
            IconButton(
              tooltip: L10n.of(context).pause,
              icon: const Icon(Icons.pause_circle_outline_outlined),
              // #Pangea
              // onPressed: state.pause,
              onPressed: state.isSending ? null : state.pause,
              // Pangea#
            ),
        Text(time),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const width = 4;
              // #Pangea
              // Waveform source: the streaming session's PCM-RMS timeline when
              // streaming, else today's amplitude timeline (byte-identical off).
              final amplitudes = state.waveformAmplitudes;
              // Pangea#
              return Row(
                mainAxisSize: .min,
                mainAxisAlignment: .end,
                children: amplitudes.reversed
                    .take((constraints.maxWidth / (width + 2)).floor())
                    .toList()
                    .reversed
                    .map(
                      (amplitude) => Container(
                        margin: const EdgeInsets.only(left: 2),
                        width: width.toDouble(),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        height: maxDecibalWidth * (amplitude / 100),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ),
        IconButton(
          style: IconButton.styleFrom(
            disabledBackgroundColor: theme.bubbleColor.withAlpha(128),
            backgroundColor: theme.bubbleColor,
            foregroundColor: theme.onBubbleColor,
          ),
          tooltip: L10n.of(context).sendAudio,
          icon: state.isSending
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator.adaptive(),
                )
              : const Icon(Icons.send_outlined),
          // #Pangea
          // One-click send (#8209): the send button always SENDS, on every
          // path. While streaming, stopAndSend stops the capture, synthesizes
          // the retained WAV, and sends it with the settled transcript
          // embedded verbatim — no intermediate stop-to-editable-review step
          // (that stop read as "pause instead of send"). The editable-review
          // machinery (stopStreamingToEditable + the TextField above) stays,
          // and stopAndSend still routes its editable/degraded states.
          // onPressed: state.isSending ? null : () => state.stopAndSend(onSend),
          // While a terminal degrade's retained-WAV recovery is in flight the
          // send stays disabled (isFinalizingToEditable covers that window) so
          // the batch payload cannot be sent before it exists.
          onPressed: state.isSending || state.isFinalizingToEditable
              ? null
              : () => state.stopAndSend(onSend),
          // Pangea#
        ),
      ],
    );

    // #Pangea
    // Batch path: today's single Row, byte-identical. Streaming path: a
    // Column whose TOP is the transcript surface and whose BOTTOM is the
    // unchanged controls Row. While recording, the surface is a read-only
    // replace-in-place live line; after stop (D7 editableClean/Dirty) it is
    // the editable TextField pre-filled with the settled final. The
    // degradation banner (D11 language gate / H9b runner-up / B4 batch
    // degrade) no longer mounts here — it renders ABOVE the composer's
    // Material box in chat_input_bar.dart (via the lifted RecordingViewModel),
    // since that box's Clip.hardEdge was cutting off the banner's shadow.
    if (!state.isStreaming && !state.isEditingTranscript) {
      return controlsRow;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.isEditingTranscript)
          EditableTranscriptDiffField(controller: state.editableController!)
        else
          _LiveTranscriptLine(text: state.liveTranscript),
        controlsRow,
      ],
    );
    // Pangea#
  }
}

// #Pangea
/// Read-only transcript surface for the streaming pilot: renders the settling
/// live transcript in place (never an append log). A display-only partial never
/// reaches the embed/bot/analytics (D10 invariant); only the guarded settled
/// final (or the user's wave-4 edit of it) is ever sent. Replaced by an
/// editable `TextField` in wave 4.
class _LiveTranscriptLine extends StatelessWidget {
  final String text;
  const _LiveTranscriptLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Editable transcript surface (D7/D10): the [TextField] renders the settled
/// transcript with the live edit-diff inline (changed words orange, unchanged
/// green — via [EditableTranscriptController.buildTextSpan]); only replaced or
/// deleted source words show struck-through beneath once the buffer diverges.
/// Public so the diff mount is widget-testable without the recording view-model.
class EditableTranscriptDiffField extends StatelessWidget {
  final EditableTranscriptController controller;
  const EditableTranscriptDiffField({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: theme.textTheme.bodyMedium,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
              ),
            ),
            if (controller.text != controller.diffBase &&
                controller.diffBase.isNotEmpty)
              ChangedOriginalWords(
                originalAsrText: controller.diffBase,
                currentText: controller.text,
              ),
          ],
        ),
      ),
    );
  }
}

// Pangea#
