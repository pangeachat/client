import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/word_audio_button.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/new_word_overlay.dart';
import 'package:fluffychat/pangea/toolbar/word_card/lemma_meaning_display.dart';
import 'package:fluffychat/pangea/toolbar/word_card/lemma_reaction_picker.dart';
import 'package:fluffychat/pangea/toolbar/word_card/message_unsubscribed_card.dart';
import 'package:fluffychat/pangea/toolbar/word_card/token_feedback_button.dart';
import 'package:fluffychat/widgets/matrix.dart';

class WordZoomWidget extends StatelessWidget {
  final PangeaTokenText token;
  final ConstructIdentifier construct;

  final String langCode;
  final VoidCallback? onClose;

  final bool wordIsNew;
  final Event? event;

  final VoidCallback? onDismissNewWordOverlay;
  final Function(LemmaInfoResponse, String)? onFlagTokenInfo;
  final Future<void> Function(String)? setEmoji;

  const WordZoomWidget({
    super.key,
    required this.token,
    required this.construct,
    required this.langCode,
    this.setEmoji,
    this.onClose,
    this.wordIsNew = false,
    this.event,
    this.onDismissNewWordOverlay,
    this.onFlagTokenInfo,
  });

  String get transformTargetId => "word-zoom-card-${token.uniqueKey}";

  LayerLink get layerLink =>
      MatrixState.pAnyState.layerLinkAndKey(transformTargetId).link;

  @override
  Widget build(BuildContext context) {
    final bool? subscribed =
        MatrixState.pangeaController.subscriptionController.isSubscribed;
    final overlayColor = Theme.of(context).scaffoldBackgroundColor;
    final showTranscript =
        MatrixState.pangeaController.userController.showTranscription;

    final Widget content = subscribed != null && !subscribed
        ? const MessageUnsubscribedCard()
        : Stack(
            children: [
              Container(
                height: AppConfig.toolbarMaxHeight - 8,
                padding: const EdgeInsets.all(12.0),
                constraints: const BoxConstraints(
                  maxWidth: AppConfig.toolbarMinWidth,
                ),
                child: CompositedTransformTarget(
                  link: layerLink,
                  child: SingleChildScrollView(
                    child: Column(
                      spacing: 12.0,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            onClose != null
                                ? IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: onClose,
                                  )
                                : const SizedBox(
                                    width: 40.0,
                                    height: 40.0,
                                  ),
                            Flexible(
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 40.0,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  token.content,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 28.0,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                    color: Theme.of(context).brightness ==
                                            Brightness.light
                                        ? AppConfig.yellowDark
                                        : AppConfig.yellowLight,
                                  ),
                                ),
                              ),
                            ),
                            onFlagTokenInfo != null
                                ? TokenFeedbackButton(
                                    textLanguage: PLanguageStore.byLangCode(
                                          langCode,
                                        ) ??
                                        LanguageModel.unknown,
                                    constructId: construct,
                                    text: token.content,
                                    onFlagTokenInfo: onFlagTokenInfo!,
                                  )
                                : const SizedBox(
                                    width: 40.0,
                                    height: 40.0,
                                  ),
                          ],
                        ),
                        Column(
                          spacing: 12.0,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            showTranscript
                                ? PhoneticTranscriptionWidget(
                                    text: token.content,
                                    textLanguage: PLanguageStore.byLangCode(
                                          langCode,
                                        ) ??
                                        LanguageModel.unknown,
                                    style: const TextStyle(fontSize: 14.0),
                                    iconSize: 24.0,
                                  )
                                : WordAudioButton(
                                    text: token.content,
                                    uniqueID: "lemma-content-${token.content}",
                                    langCode: langCode,
                                    iconSize: 24.0,
                                  ),
                            LemmaReactionPicker(
                              construct: construct,
                              langCode: langCode,
                              event: event,
                              setEmoji: setEmoji,
                            ),
                            LemmaMeaningDisplay(
                              langCode: langCode,
                              constructId: construct,
                              text: token.content,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              wordIsNew
                  ? NewWordOverlay(
                      key: ValueKey(transformTargetId),
                      overlayColor: overlayColor,
                      transformTargetId: transformTargetId,
                      onDismiss: onDismissNewWordOverlay,
                    )
                  : const SizedBox.shrink(),
            ],
          );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 4.0,
          ),
          borderRadius: const BorderRadius.all(
            Radius.circular(AppConfig.borderRadius),
          ),
        ),
        height: AppConfig.toolbarMaxHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            content,
          ],
        ),
      ),
    );
  }
}
