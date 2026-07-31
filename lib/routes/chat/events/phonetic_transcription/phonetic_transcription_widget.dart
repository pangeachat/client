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
  bool _isPlaying = false;

  @override
  void dispose() {
    TtsController.stop(
      text: widget.text,
      langCode: widget.textLanguage.langCode,
      pos: widget.pos,
      morph: widget.morph,
    );
    super.dispose();
  }

  Future<void> _handleAudioTap(String targetId) async {
    if (_isPlaying) {
      await TtsController.stop(
        text: widget.text,
        langCode: widget.textLanguage.langCode,
        pos: widget.pos,
        morph: widget.morph,
      );
      setState(() => _isPlaying = false);
    } else {
      await TtsController.tryToSpeak(
        widget.text,
        context: context,
        targetID: targetId,
        langCode: widget.textLanguage.langCode,
        pos: widget.pos,
        morph: widget.morph,
        onStart: () {
          if (mounted) setState(() => _isPlaying = true);
        },
        onStop: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetId = 'phonetic-transcription-${widget.text}-$hashCode';
    if (widget.textOnly) {
      return PhoneticTranscriptionBuilder(
        key: Key(targetId),
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

        return HoverBuilder(
          builder: (context, hovering) {
            return Tooltip(
              message: _isPlaying
                  ? L10n.of(context).stop
                  : L10n.of(context).playAudio,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleAudioTap(targetId),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: hovering
                        ? Colors.grey.withAlpha((0.2 * 255).round())
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: CompositedTransformTarget(
                    link: MatrixState.pAnyState.layerLinkAndKey(targetId).link,
                    child: KeyedSubtree(
                      key: MatrixState.pAnyState.layerLinkAndKey(targetId).key,
                      child: Row(
                        spacing: 8.0,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              disambiguate(
                                state.value.pronunciations,
                                pos: widget.pos,
                                morph: widget.morph,
                              ).displayTranscription,
                              textScaler: TextScaler.noScaling,
                              style:
                                  widget.style ??
                                  Theme.of(context).textTheme.bodyMedium,
                              maxLines: widget.maxLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            _isPlaying ? Icons.pause_outlined : Icons.volume_up,
                            size: widget.iconSize ?? 24,
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
      },
    );
  }
}
