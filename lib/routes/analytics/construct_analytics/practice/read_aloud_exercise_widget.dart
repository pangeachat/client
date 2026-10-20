import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/analytics/listening_exposure_declaration.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/language_semantics.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_match.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_recorder.dart';
import 'package:fluffychat/routes/chat/audio_player.dart';
import 'package:fluffychat/routes/chat/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_audio_card.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// One read-aloud item: the sentence, the reference player, the mic, and after
/// a take the compare row and the verdict. See
/// practice-exercises.instructions.md, "Speaking practice".
///
/// The widget owns the item's [ReadAloudRecorder] and reports upward once:
/// [onRecorded] with whether the target was heard, on the first full pass or
/// when the tries run out; [onMicUnavailable] when the microphone is refused
/// or absent. More takes after that are the learner comparing, not answering.
class ReadAloudExerciseWidget extends StatefulWidget {
  final ReadAloudPracticeExerciseModel exercise;
  final PangeaAudioFile? referenceAudio;
  final bool hearItFirst;
  final AudioPlaybackSpeedController playbackSpeedController;
  final ReadAloudRecorder Function(List<String> reference) recorderFactory;
  final void Function(bool heard) onRecorded;
  final VoidCallback onContinue;
  final VoidCallback onMicUnavailable;
  final VoidCallback onSkip;

  const ReadAloudExerciseWidget({
    super.key,
    required this.exercise,
    required this.referenceAudio,
    required this.hearItFirst,
    required this.playbackSpeedController,
    required this.recorderFactory,
    required this.onRecorded,
    required this.onContinue,
    required this.onMicUnavailable,
    required this.onSkip,
  });

  @override
  State<ReadAloudExerciseWidget> createState() =>
      _ReadAloudExerciseWidgetState();
}

class _ReadAloudExerciseWidgetState extends State<ReadAloudExerciseWidget> {
  static const double _playerWidth = 300.0;

  late final ReadAloudRecorder _recorder;
  bool _recorded = false;
  bool _micReported = false;

  /// Remounting the reference player disposes it, which is how a tap on the
  /// mic stops a reference still playing: the reference and the mic never run
  /// together.
  int _referencePlayer = 0;
  late bool _autoplayReference;

  @override
  void initState() {
    super.initState();
    _autoplayReference = widget.hearItFirst && widget.referenceAudio != null;
    _recorder = widget.recorderFactory([
      for (final token in widget.exercise.referenceTokens) token.text.content,
    ]);
    _recorder.addListener(_onRecorder);
  }

  @override
  void dispose() {
    _recorder.removeListener(_onRecorder);
    _recorder.dispose();
    super.dispose();
  }

  bool get _targetHeard {
    final index = widget.exercise.targetIndex;
    return index >= 0 &&
        index < _recorder.heard.length &&
        _recorder.heard[index];
  }

  void _onRecorder() {
    if (_recorder.phase == ReadAloudPhase.done && !_recorded) {
      if (_targetHeard || _recorder.triesLeft <= 0) {
        _recorded = true;
        widget.onRecorded(_targetHeard);
      }
    }
    if (_recorder.phase == ReadAloudPhase.micUnavailable && !_micReported) {
      _micReported = true;
      widget.onMicUnavailable();
    }
    if (mounted) setState(() {});
  }

  Future<void> _onMicTap() async {
    if (_recorder.phase == ReadAloudPhase.recording) {
      await _recorder.stop();
      return;
    }
    setState(() {
      _autoplayReference = false;
      _referencePlayer++;
    });
    await _recorder.start();
  }

  /// The sentence, every word styled by whether it has been heard. Gaps
  /// between tokens come from the displayed text, so punctuation and spacing
  /// read exactly as the learner met them.
  List<InlineSpan> _sentenceSpans(BuildContext context) {
    final exercise = widget.exercise;
    final theme = Theme.of(context);
    final pangea = theme.pangea;
    final chars = exercise.referenceText.characters.toList();
    final base = exercise.exampleTokens.isEmpty
        ? 0
        : exercise.exampleTokens.first.text.offset;
    final hasTake = _recorder.lastTake != null;
    final target = exercise.targetIndex;

    final spans = <InlineSpan>[];
    var previousEnd = 0;
    var wordIndex = 0;
    for (final token in exercise.exampleTokens) {
      final start = (token.text.offset - base).clamp(0, chars.length);
      final end = (start + token.text.content.characters.length).clamp(
        0,
        chars.length,
      );
      if (start > previousEnd) {
        spans.add(TextSpan(text: chars.sublist(previousEnd, start).join()));
      }
      final isWord = isSpokenWord(token.text.content);
      Color? color;
      var weight = FontWeight.normal;
      if (isWord) {
        final heard =
            wordIndex < _recorder.heard.length && _recorder.heard[wordIndex];
        if (heard) {
          color = pangea.successGraphic;
          weight = FontWeight.bold;
        } else if (hasTake) {
          color = pangea.warningGraphic;
        }
        if (wordIndex == target) weight = FontWeight.bold;
        wordIndex++;
      }
      spans.add(
        TextSpan(
          text: token.text.content,
          style: TextStyle(color: color, fontWeight: weight),
        ),
      );
      previousEnd = end > previousEnd ? end : previousEnd;
    }
    if (previousEnd < chars.length) {
      spans.add(TextSpan(text: chars.sublist(previousEnd).join()));
    }
    return spans;
  }

  Widget _player(
    BuildContext context, {
    required Key key,
    required String label,
    required PangeaAudioFile file,
    required String eventId,
    required bool autoplay,
    required ListeningExposureDeclaration exposure,
  }) {
    final theme = Theme.of(context);
    final exercise = widget.exercise;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        SizedBox(
          width: _playerWidth,
          height: 60.0,
          child: AudioPlayerWidget(
            null,
            key: key,
            color: theme.colorScheme.primary,
            linkColor: theme.colorScheme.secondary,
            fontSize: AppConfig.messageFontSize,
            eventId: eventId,
            roomId: exercise.roomId ?? '',
            senderId: Matrix.of(context).client.userID!,
            matrixFile: file,
            autoplay: autoplay,
            playbackSpeedController: widget.playbackSpeedController,
            // No listening category, like the listening exercise's player: the
            // shared-player practice surfaces stay dark until #8411 lands.
            exposure: exposure,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final exercise = widget.exercise;
    final phase = _recorder.phase;
    final take = _recorder.lastTake;
    final reference = widget.referenceAudio;
    final canRecord =
        _recorder.triesLeft > 0 &&
        (phase == ReadAloudPhase.idle ||
            phase == ReadAloudPhase.done ||
            phase == ReadAloudPhase.failed);
    final recording = phase == ReadAloudPhase.recording;
    final starting = phase == ReadAloudPhase.starting;

    final String micLabel = recording
        ? l10n.readAloudStop
        : starting
        ? l10n.readAloudStarting
        : _recorder.lastTake == null || _recorder.unheardCount == 0
        ? l10n.readAloudRecord
        : l10n.readAloudMicLabel(_recorder.unheardCount);

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12.0,
      children: [
        if (take == null && phase == ReadAloudPhase.idle)
          Text(
            l10n.readAloudInstruction,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LanguageSemantics(
            langCode: exercise.langCode,
            child: Text.rich(
              TextSpan(children: _sentenceSpans(context)),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        // What the mic is doing: getting ready (nothing is recorded yet, so
        // a learner who starts on the tap is told to wait, not cut off), then
        // listening, then the live transcript, replace-in-place as it
        // settles, as the voice-message recorder shows it while the mic is hot.
        if (starting || recording || phase == ReadAloudPhase.finalizing)
          Container(
            constraints: const BoxConstraints(minHeight: 24.0),
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              starting
                  ? l10n.readAloudStarting
                  : recording && _recorder.liveTranscript.isEmpty
                  ? l10n.readAloudListening
                  : _recorder.liveTranscript,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        // Stacked, the reference over the learner's take, each with the
        // volume bars every recording in the app shows, so the shapes compare
        // as well as the sounds.
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8.0,
          children: [
            if (reference != null)
              _player(
                context,
                key: ValueKey('read_aloud_reference_$_referencePlayer'),
                label: l10n.readAloudExample,
                file: reference,
                eventId: '${exercise.eventId}_read_aloud_reference',
                autoplay: _autoplayReference,
                exposure: ListeningExposureDeclaration.ofTokens(
                  exercise.exampleTokens,
                  langCode: exercise.langCode,
                ),
              ),
            if (take?.wav != null)
              _player(
                context,
                key: ValueKey('read_aloud_take_${_recorder.triesUsed}'),
                label: l10n.readAloudYourRecording,
                file: PangeaAudioFile(
                  bytes: take!.wav!,
                  name: 'read_aloud_take.wav',
                  mimeType: 'audio/wav',
                  duration: take.duration.inMilliseconds,
                  waveform: take.waveform,
                  tokens: null,
                ),
                eventId:
                    '${exercise.eventId}_read_aloud_take_${_recorder.triesUsed}',
                autoplay: false,
                // The learner's own voice is not exposure to the words.
                exposure: const ListeningExposureDeclaration.exempt(
                  'the learner hearing their own read-aloud recording',
                ),
              ),
          ],
        ),
        if (phase == ReadAloudPhase.done && take != null) ...[
          Text(
            _recorder.allHeard
                ? l10n.readAloudHeardAll
                : [
                    l10n.readAloudNotHeard(_recorder.unheardCount),
                    if (!_targetHeard && _recorder.triesLeft > 0)
                      l10n.readAloudTriesLeft(_recorder.triesLeft),
                  ].join(' · '),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (take.transcript.trim().isNotEmpty)
            Text(
              l10n.readAloudHeardTranscript(take.transcript),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
        if (phase == ReadAloudPhase.failed)
          Text(
            l10n.readAloudTranscribeFailed,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        SizedBox(
          width: 72.0,
          height: 72.0,
          child: IconButton.filled(
            iconSize: 36.0,
            tooltip: micLabel,
            onPressed: canRecord || recording ? _onMicTap : null,
            icon: switch (phase) {
              ReadAloudPhase.recording => const Icon(Icons.stop),
              ReadAloudPhase.starting ||
              ReadAloudPhase.finalizing => const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(),
              ),
              _ => const Icon(Icons.mic),
            },
            style: IconButton.styleFrom(
              backgroundColor: recording
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              foregroundColor: recording
                  ? theme.colorScheme.onError
                  : theme.colorScheme.onPrimary,
            ),
          ),
        ),
        // Discards the recording in progress and begins a fresh one, without
        // spending a take.
        if (recording)
          TextButton.icon(
            onPressed: _recorder.restart,
            icon: const Icon(Icons.replay),
            label: Text(l10n.readAloudStartOver),
          ),
        // Skip is always offered: a learner may be somewhere they cannot
        // speak, or the recognizer may not be taking their recording. It
        // records nothing but the usual skip, so the word comes back later.
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            spacing: 8.0,
            children: [
              TextButton(onPressed: widget.onSkip, child: Text(l10n.skip)),
              Expanded(
                child: ElevatedButton(
                  onPressed: _recorded ? widget.onContinue : null,
                  child: Text(
                    l10n.continueText,
                    style: const TextStyle(fontSize: 16.0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
