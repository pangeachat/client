import 'package:flutter/material.dart';

import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';

/// The D9 "learner-edited transcript" indicator: a small neutral edit pencil
/// shown on a voice message whose `user_stt` provenance carries `edited == true`
/// (read via [PangeaMessageEvent.isTranscriptEdited] /
/// [sttTranscriptEditedFromUserStt]).
///
/// Renders NOTHING for a verbatim message, so callers can drop it into a Row
/// unconditionally. Uses the Material edit pencil in the muted meta colour
/// (onSurfaceVariant) — an edit is normal, not a warning.
class TranscriptEditedFlag extends StatelessWidget {
  const TranscriptEditedFlag({
    required this.edited,
    this.size = 16.0,
    this.color,
    this.semanticLabel,
    super.key,
  });

  /// Whether the transcript was learner-edited. When `false` the widget is an
  /// empty [SizedBox] — no pencil for a verbatim transcript.
  final bool edited;

  final double size;

  /// Colour of the pencil. Callers that render the flag ON a coloured bubble
  /// (the audio tile mount) MUST pass the bubble's own foreground colour — the
  /// same `textColor` the tile's waveform/timestamp use — so the pencil
  /// contrasts with the bubble. When null it falls back to the muted meta
  /// colour, which only reads on the default scaffold surface.
  final Color? color;

  /// Accessibility label for the indicator; defaults to a plain description.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (!edited) return const SizedBox.shrink();
    // A neutral edit pencil (like the "edited" mark on a text message), NOT a
    // warning triangle: editing the transcript is normal behaviour, not an
    // error. On the audio bubble the caller passes the tile's `textColor`
    // (dark on the light voice bubble); onSurfaceVariant is only the fallback.
    return Icon(
      Icons.edit_outlined,
      size: size,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      semanticLabel: semanticLabel ?? 'Edited transcript',
    );
  }
}

/// Production mount for the D9 edited-transcript flag on an audio message
/// (message_content.dart audio case): binds the REAL
/// [PangeaMessageEvent.isTranscriptEdited] provenance reader to
/// [TranscriptEditedFlag]. Renders the edit pencil iff the sent voice
/// message's `user_stt.edited == true`, nothing otherwise. This is the widget
/// the audio bubble actually mounts, so the flag reads a real message's
/// provenance rather than a caller-supplied bool.
class AudioMessageEditedFlag extends StatelessWidget {
  const AudioMessageEditedFlag({
    required this.pangeaMessageEvent,
    this.size = 16.0,
    this.color,
    super.key,
  });

  final PangeaMessageEvent pangeaMessageEvent;
  final double size;

  /// Pencil colour — the audio tile's `textColor`, so the marker reads on the
  /// voice bubble. See [TranscriptEditedFlag.color].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TranscriptEditedFlag(
      edited: pangeaMessageEvent.isTranscriptEdited,
      size: size,
      color: color,
    );
  }

  /// The audio-bubble mount decision, factored out of message_content.dart so
  /// the wrap logic is unit-testable without rendering the MatrixState-singleton
  /// -gated AudioPlayerWidget subtree. Returns [audioBody] UNCHANGED unless the
  /// message's `user_stt.edited == true`, in which case it overlays a passive
  /// marker without changing the audio tile's dimensions. The focused-message
  /// surface owns transcript disclosure and the word-level diff.
  static Widget wrap(
    Widget audioBody,
    PangeaMessageEvent? pangeaMessageEvent, {
    Color? color,
  }) {
    if (pangeaMessageEvent?.isTranscriptEdited != true) return audioBody;
    return Stack(
      key: const Key('audio-edited-marker-stack'),
      clipBehavior: Clip.none,
      children: [
        audioBody,
        PositionedDirectional(
          end: 8,
          bottom: 4,
          child: IgnorePointer(
            child: AudioMessageEditedFlag(
              pangeaMessageEvent: pangeaMessageEvent!,
              size: 14,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
