import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/word_audio_button.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/routes/chat/events/tokens/tokens_util.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/new_word_overlay.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/lemma_meaning_display.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/lemma_reaction_picker.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/message_unsubscribed_card.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/token_feedback_button.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class WordZoomWidget extends StatelessWidget {
  final PangeaTokenText token;
  final ConstructIdentifier construct;

  final String langCode;
  final VoidCallback? onClose;

  final Event? event;

  /// POS tag for PT v2 disambiguation (e.g. "VERB").
  final String pos;

  /// Morph features for PT v2 disambiguation (e.g. {"Tense": "Past"}).
  final Map<String, String>? morph;

  final bool enableEmojiSelection;
  final bool enableEmojiReactions;
  final bool enableAnalyticsNavigation;

  final Function(LemmaInfoResponse, PTRequest, PTResponse)? onFlagTokenInfo;
  final ValueNotifier<int>? reloadNotifier;
  final double? maxWidth;

  const WordZoomWidget({
    super.key,
    required this.token,
    required this.construct,
    required this.langCode,
    required this.pos,
    this.onClose,
    this.event,
    this.morph,
    this.enableEmojiSelection = true,
    this.enableEmojiReactions = true,
    this.enableAnalyticsNavigation = false,
    this.onFlagTokenInfo,
    this.reloadNotifier,
    this.maxWidth,
  });

  void _showNewWordOverlay(BuildContext context) {
    if (TokensUtil.instance.isRecentlyCollected(token)) {
      NewWordOverlay.show(
        context: context,
        target: token.wordCardTargetKey,
        overlayKey: "new-word-${token.uniqueKey}",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      _showNewWordOverlay(context);
    });

    final showTranscript =
        MatrixState.pangeaController.userController.showTranscription;

    final Widget content =
        !MatrixState
            .pangeaController
            .subscriptionController
            .showSubscriptionGatedContent
        ? MessageUnsubscribedCard(token: token, onClose: onClose)
        : Stack(
            children: [
              Container(
                height: AppConfig.toolbarMaxHeight - 8,
                padding: const EdgeInsets.all(12.0),
                constraints: BoxConstraints(
                  maxWidth: maxWidth ?? AppConfig.toolbarMinWidth,
                ),
                child: Column(
                  spacing: 12.0,
                  children: [
                    SizedBox(
                      height: 40.0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          onClose != null
                              ? IconButton(
                                  tooltip: L10n.of(context).close,
                                  color: Theme.of(context).iconTheme.color,
                                  icon: const Icon(Icons.close),
                                  onPressed: onClose,
                                )
                              : const SizedBox(width: 40.0, height: 40.0),
                          Flexible(
                            child: InkWell(
                              onTap: enableAnalyticsNavigation
                                  ? () =>
                                        AnalyticsNavigationUtil.navigateToAnalytics(
                                          context: context,
                                          view: ProgressIndicatorEnum.wordsUsed,
                                          construct: construct,
                                        )
                                  : null,
                              borderRadius: BorderRadius.circular(8.0),
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
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.light
                                        ? AppConfig.yellowDark
                                        : AppConfig.yellowLight,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          onFlagTokenInfo != null
                              ? TokenFeedbackButton(
                                  textLanguage:
                                      PLanguageStore.byLangCode(langCode) ??
                                      LanguageModel.unknown,
                                  constructId: construct,
                                  text: token.content,
                                  onFlagTokenInfo: onFlagTokenInfo!,
                                  messageInfo: event?.content ?? {},
                                )
                              : const SizedBox(width: 40.0, height: 40.0),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        spacing: 4.0,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          showTranscript
                              ? PhoneticTranscriptionWidget(
                                  text: token.content,
                                  textLanguage:
                                      PLanguageStore.byLangCode(langCode) ??
                                      LanguageModel.unknown,
                                  pos: pos,
                                  morph: morph,
                                  style: const TextStyle(fontSize: 14.0),
                                  iconSize: 24.0,
                                  maxLines: 2,
                                  reloadNotifier: reloadNotifier,
                                )
                              : WordAudioButton(
                                  text: token.content,
                                  pos: pos,
                                  morph: morph,
                                  uniqueID: "lemma-content-${token.content}",
                                  langCode: langCode,
                                  iconSize: 24.0,
                                ),
                          LemmaReactionPicker(
                            constructId: construct,
                            langCode: langCode,
                            event: event,
                            enableSelection: enableEmojiSelection,
                            enableReactions: enableEmojiReactions,
                            form: token.content,
                          ),
                          LemmaMeaningDisplay(
                            langCode: langCode,
                            constructId: construct,
                            text: token.content,
                            messageInfo: event?.content ?? {},
                            reloadNotifier: reloadNotifier,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    return GestureDetector(
      onTap: () {
        // Absorb taps to prevent them from propagating
        // to widgets below and closing the overlay.
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(
              width: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
            borderRadius: const BorderRadius.all(Radius.circular(25)),
          ),
          height: AppConfig.toolbarMaxHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [content],
          ),
        ),
      ),
    );
  }
}
