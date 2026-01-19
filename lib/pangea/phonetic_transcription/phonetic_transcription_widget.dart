import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_builder.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PhoneticTranscriptionWidget extends StatefulWidget {
  final String text;
  final LanguageModel textLanguage;

  final TextStyle? style;
  final double? iconSize;
  final Color? iconColor;
  final int? maxLines;

  final VoidCallback? onTranscriptionFetched;
  final ValueNotifier<int>? reloadNotifier;

  const PhoneticTranscriptionWidget({
    super.key,
    required this.text,
    required this.textLanguage,
    this.style,
    this.iconSize,
    this.iconColor,
    this.maxLines,
    this.onTranscriptionFetched,
    this.reloadNotifier,
  });

  @override
  State<PhoneticTranscriptionWidget> createState() =>
      _PhoneticTranscriptionWidgetState();
}

class _PhoneticTranscriptionWidgetState
    extends State<PhoneticTranscriptionWidget> {
  bool _isPlaying = false;

  Future<void> _handleAudioTap(String targetId) async {
    if (_isPlaying) {
      await TtsController.stop();
      setState(() => _isPlaying = false);
    } else {
      await TtsController.tryToSpeak(
        widget.text,
        context: context,
        targetID: targetId,
        langCode: widget.textLanguage.langCode,
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
    return HoverBuilder(
      builder: (context, hovering) {
        return GestureDetector(
          onTap: () => _handleAudioTap(targetId),
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
              child: PhoneticTranscriptionBuilder(
                key: MatrixState.pAnyState.layerLinkAndKey(targetId).key,
                textLanguage: widget.textLanguage,
                text: widget.text,
                reloadNotifier: widget.reloadNotifier,
                builder: (context, controller) {
                  return switch (controller.state) {
                    AsyncError(error: final error) =>
                      error is UnsubscribedException
                          ? ErrorIndicator(
                              message: L10n.of(context)
                                  .subscribeToUnlockTranscriptions,
                              onTap: () {
                                MatrixState
                                    .pangeaController.subscriptionController
                                    .showPaywall(context);
                              },
                            )
                          : ErrorIndicator(
                              message:
                                  L10n.of(context).failedToFetchTranscription,
                            ),
                    AsyncLoaded<String>(value: final transcription) => Row(
                        spacing: 8.0,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              transcription,
                              textScaler: TextScaler.noScaling,
                              style: widget.style ??
                                  Theme.of(context).textTheme.bodyMedium,
                              maxLines: widget.maxLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Tooltip(
                            message: _isPlaying
                                ? L10n.of(context).stop
                                : L10n.of(context).playAudio,
                            child: Icon(
                              _isPlaying
                                  ? Icons.pause_outlined
                                  : Icons.volume_up,
                              size: widget.iconSize ?? 24,
                              color: widget.iconColor ??
                                  Theme.of(context).iconTheme.color,
                            ),
                          ),
                        ],
                      ),
                    _ => const TextLoadingShimmer(
                        width: 125.0,
                        height: 20.0,
                      ),
                  };
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
