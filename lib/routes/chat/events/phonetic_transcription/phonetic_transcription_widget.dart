import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/phonetic_transcription_builder.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_disambiguation.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/text_loading_shimmer.dart';

class PhoneticTranscriptionWidget extends StatefulWidget {
  final String text;
  final LanguageModel textLanguage;

  /// POS tag for disambiguation (from PangeaToken, e.g. "VERB").
  final String pos;

  /// Morph features for disambiguation (from PangeaToken).
  final Map<String, String>? morph;

  final TextStyle? style;
  final double? iconSize;
  final Color? iconColor;
  final int? maxLines;

  final VoidCallback? onTranscriptionFetched;
  final ValueNotifier<int>? reloadNotifier;

  /// If true, only show the transcription text without audio controls or hover effects
  final bool textOnly;

  const PhoneticTranscriptionWidget({
    super.key,
    required this.text,
    required this.textLanguage,
    required this.pos,
    this.morph,
    this.style,
    this.iconSize,
    this.iconColor,
    this.maxLines,
    this.onTranscriptionFetched,
    this.reloadNotifier,
    this.textOnly = false,
  });

  @override
  State<PhoneticTranscriptionWidget> createState() =>
      _PhoneticTranscriptionWidgetState();
}

class _PhoneticTranscriptionWidgetState
    extends State<PhoneticTranscriptionWidget> {
  /// Target id of the affordance currently playing, or null. The heteronym
  /// fallback renders one affordance per pronunciation, so a plain bool
  /// can't say which one to mark.
  String? _playingId;

  /// Target id whose backend TTS fetch is in flight — drives the loading
  /// state on the play affordance (#2564). Scoped by target id, see
  /// [TtsLoadingEvent].
  String? _loadingId;

  StreamSubscription<TtsLoadingEvent>? _loadingSubscription;

  String get _baseTargetId => 'phonetic-transcription-${widget.text}-$hashCode';

  @override
  void initState() {
    super.initState();
    _loadingSubscription = TtsController.loadingChoreoStream.stream.listen((
      event,
    ) {
      final targetId = event.targetId;
      if (targetId == null || !targetId.startsWith(_baseTargetId)) return;
      if (mounted) {
        setState(() => _loadingId = event.isLoading ? targetId : null);
      }
    });
  }

  @override
  void dispose() {
    _loadingSubscription?.cancel();
    TtsController.stop(
      text: widget.text,
      langCode: widget.textLanguage.langCode,
      pos: widget.pos,
      morph: widget.morph,
    );
    super.dispose();
  }

  /// Play or stop one affordance. [ttsPhoneme] is set only on the
  /// heteronym-fallback buttons, where each button speaks its own
  /// pronunciation; the single/matched affordance omits it and lets the
  /// controller resolve the phoneme from the PT cache as before.
  Future<void> _handleAudioTap(String targetId, {String? ttsPhoneme}) async {
    if (_playingId == targetId) {
      await TtsController.stop(
        text: widget.text,
        langCode: widget.textLanguage.langCode,
        pos: widget.pos,
        morph: widget.morph,
      );
      if (mounted) setState(() => _playingId = null);
    } else {
      await TtsController.tryToSpeak(
        widget.text,
        context: context,
        targetID: targetId,
        langCode: widget.textLanguage.langCode,
        pos: widget.pos,
        morph: widget.morph,
        ttsPhoneme: ttsPhoneme,
        onStart: () {
          if (mounted) setState(() => _playingId = targetId);
        },
        onStop: () {
          if (mounted && _playingId == targetId) {
            setState(() => _playingId = null);
          }
        },
      );
    }
  }

  TextStyle? _textStyle(BuildContext context) =>
      widget.style ?? Theme.of(context).textTheme.bodyMedium;

  /// Sized just over the text so the icon reads as part of it rather than a
  /// separate control (#2564 asked for a smaller, more merged play icon).
  double _iconSize(BuildContext context) =>
      widget.iconSize ?? ((_textStyle(context)?.fontSize ?? 14.0) + 4.0);

  /// One playable transcription: text + play/pause icon (or a spinner while
  /// the backend fetch for THIS affordance is in flight), with the tooltip,
  /// hover highlight, and popup anchor scoped to it.
  Widget _playable(
    BuildContext context, {
    required String targetId,
    required String label,
    String? ttsPhoneme,
  }) {
    final isPlaying = _playingId == targetId;
    final isLoading = _loadingId == targetId;
    final iconSize = _iconSize(context);
    return HoverBuilder(
      builder: (context, hovering) {
        return Tooltip(
          message: isPlaying
              ? L10n.of(context).stop
              : L10n.of(context).playAudio,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleAudioTap(targetId, ttsPhoneme: ttsPhoneme),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: hovering
                    ? Colors.grey.withAlpha((0.2 * 255).round())
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: CompositedTransformTarget(
                link: MatrixState.pAnyState.layerLinkAndKey(targetId).link,
                child: KeyedSubtree(
                  key: MatrixState.pAnyState.layerLinkAndKey(targetId).key,
                  child: Row(
                    spacing: 4.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          textScaler: TextScaler.noScaling,
                          style: _textStyle(context),
                          maxLines: widget.maxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLoading)
                        SizedBox(
                          width: iconSize - 4.0,
                          height: iconSize - 4.0,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      else
                        Icon(
                          isPlaying ? Icons.pause_outlined : Icons.volume_up,
                          size: iconSize,
                          color:
                              widget.iconColor ??
                              Theme.of(context).iconTheme.color,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // PT covers isolated words only (design doc §5). Practice hints route
    // whole example sentences through this widget; requesting those spends
    // an LLM call per unique sentence and renders a meaningless chain of
    // per-word transcriptions, so phrases render nothing at all (#8077).
    if (isPhraseSurface(widget.text)) return const SizedBox.shrink();

    if (widget.textOnly) {
      return PhoneticTranscriptionBuilder(
        key: Key(_baseTargetId),
        textLanguage: widget.textLanguage,
        text: widget.text,
        reloadNotifier: widget.reloadNotifier,
        builder: (context, controller) {
          return switch (controller.state) {
            AsyncError() => const SizedBox.shrink(),
            AsyncLoaded<PTResponse>(value: final ptResponse) => Text(
              disambiguate(
                ptResponse.pronunciations,
                pos: widget.pos,
                morph: widget.morph,
              ).displayTranscription,
              textScaler: TextScaler.noScaling,
              style: widget.style ?? Theme.of(context).textTheme.bodyMedium,
              maxLines: widget.maxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            _ => SizedBox(
              width: 30.0,
              height: 16.0,
              child: TextLoadingShimmer(width: 30.0, height: 16.0),
            ),
          };
        },
      );
    }

    return PhoneticTranscriptionBuilder(
      textLanguage: widget.textLanguage,
      text: widget.text,
      reloadNotifier: widget.reloadNotifier,
      builder: (context, controller) {
        final state = controller.state;

        // Only a loaded transcription is playable, so the play affordance —
        // tooltip, hover highlight and tap target — wraps that state alone.
        // While loading there is no pronunciation yet and on failure there
        // never will be; either way the audio icon is absent, so a "Play"
        // tooltip over the shimmer or the error chip promises audio that isn't
        // there (#7843). Padding matches the container below so the layout
        // doesn't shift when the transcription lands.
        if (state is! AsyncLoaded<PTResponse>) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: switch (state) {
              AsyncError(error: final error) =>
                error is UnsubscribedException
                    ? ErrorIndicator(
                        message: L10n.of(
                          context,
                        ).subscribeToUnlockTranscriptions,
                        onTap: () => context.go(
                          WorkspaceNav.openSettings(
                            GoRouterState.of(context).uri,
                            page: 'subscription',
                          ),
                        ),
                      )
                    : ErrorIndicator(
                        message: L10n.of(context).failedToFetchTranscription,
                      ),
              _ => const TextLoadingShimmer(width: 125.0, height: 20.0),
            },
          );
        }

        final result = disambiguate(
          state.value.pronunciations,
          pos: widget.pos,
          morph: widget.morph,
        );

        // Undisambiguated heteronym: every pronunciation individually
        // playable with its own tts_phoneme, instead of one slash-joined
        // string whose audio plays an arbitrary reading (design doc §3.3,
        // #2564).
        if (result.isAmbiguous) {
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (i, pronunciation) in result.all.indexed)
                _playable(
                  context,
                  targetId: '$_baseTargetId-$i',
                  label: pronunciation.transcription,
                  ttsPhoneme: pronunciation.ttsPhoneme,
                ),
            ],
          );
        }

        return _playable(
          context,
          targetId: _baseTargetId,
          label: result.displayTranscription,
        );
      },
    );
  }
}
