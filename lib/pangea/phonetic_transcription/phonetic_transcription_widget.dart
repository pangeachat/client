import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
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

  final VoidCallback? onTranscriptionFetched;

  const PhoneticTranscriptionWidget({
    super.key,
    required this.text,
    required this.textLanguage,
    this.style,
    this.iconSize,
    this.iconColor,
    this.onTranscriptionFetched,
  });

  @override
  State<PhoneticTranscriptionWidget> createState() =>
      _PhoneticTranscriptionWidgetState();
}

class _PhoneticTranscriptionWidgetState
    extends State<PhoneticTranscriptionWidget> {
  bool _isPlaying = false;

  Future<void> _handleAudioTap() async {
    if (_isPlaying) {
      await TtsController.stop();
      setState(() => _isPlaying = false);
    } else {
      await TtsController.tryToSpeak(
        widget.text,
        context: context,
        targetID: 'phonetic-transcription-${widget.text}',
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
    return HoverBuilder(
      builder: (context, hovering) {
        return GestureDetector(
          onTap: _handleAudioTap,
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
              link: MatrixState.pAnyState
                  .layerLinkAndKey("phonetic-transcription-${widget.text}")
                  .link,
              child: PhoneticTranscriptionBuilder(
                key: MatrixState.pAnyState
                    .layerLinkAndKey("phonetic-transcription-${widget.text}")
                    .key,
                textLanguage: widget.textLanguage,
                text: widget.text,
                builder: (context, controller) {
                  if (controller.isError) {
                    return controller.error is UnsubscribedException
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
                          );
                  }

                  if (controller.isLoading ||
                      controller.transcription == null) {
                    return const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }

                  return Row(
                    spacing: 8.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          controller.transcription!,
                          textScaler: TextScaler.noScaling,
                          style: widget.style ??
                              Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Tooltip(
                        message: _isPlaying
                            ? L10n.of(context).stop
                            : L10n.of(context).playAudio,
                        child: Icon(
                          _isPlaying ? Icons.pause_outlined : Icons.volume_up,
                          size: widget.iconSize ?? 24,
                          color: widget.iconColor ??
                              Theme.of(context).iconTheme.color,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
