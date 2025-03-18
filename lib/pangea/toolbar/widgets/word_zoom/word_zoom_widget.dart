import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_popup.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/gain_points_animation.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/lemmas/construct_xp_widget.dart';
import 'package:fluffychat/pangea/lemmas/lemma_emoji_row.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/word_audio_button.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/lemma_meaning_widget.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/lemma_widget.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/morphs/morphological_list_item.dart';
import 'package:fluffychat/widgets/matrix.dart';

class WordZoomWidget extends StatelessWidget {
  final PangeaToken token;
  final PangeaMessageEvent messageEvent;
  final TtsController tts;
  final MessageOverlayController overlayController;

  const WordZoomWidget({
    super.key,
    required this.token,
    required this.messageEvent,
    required this.tts,
    required this.overlayController,
  });

  PangeaToken get _selectedToken => overlayController.selectedToken!;

  void onEditDone() => overlayController.initializeTokensAndMode();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppConfig.toolbarMinHeight,
        maxHeight: AppConfig.toolbarMaxHeight,
        maxWidth: AppConfig.toolbarMinWidth,
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          const Positioned(
            child: PointsGainedAnimation(
              origin: AnalyticsUpdateOrigin.wordZoom,
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 40,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      //@ggurdin - might need to play with size to properly center
                      const SizedBox(width: 40),
                      LemmaWidget(
                        token: _selectedToken,
                        pangeaMessageEvent: messageEvent,
                        // onEdit: () => _setHideCenterContent(true),
                        onEdit: () {
                          debugPrint("what are we doing edits with?");
                        },
                        onEditDone: () {
                          debugPrint("what are we doing edits with?");
                          onEditDone();
                        },
                        tts: tts,
                        messageMode: overlayController.toolbarMode,
                      ),
                      ConstructXpWidget(
                        id: token.vocabConstructID,
                        onTap: () => showDialog<AnalyticsPopupWrapper>(
                          context: context,
                          builder: (context) => AnalyticsPopupWrapper(
                            constructZoom: token.vocabConstructID,
                            view: ConstructTypeEnum.vocab,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 8.0,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      constraints: const BoxConstraints(
                        minHeight: 40,
                      ),
                      alignment: Alignment.center,
                      child: LemmaEmojiRow(
                        cId: _selectedToken.vocabConstructID,
                        onTap: () => overlayController.updateToolbarMode(
                          MessageMode.wordEmoji,
                        ),
                        isSelected: overlayController.toolbarMode ==
                            MessageMode.wordEmoji,
                        removeCallback: () => overlayController
                            .updateReadingAssistanceInputBarChoices(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 8.0,
                ),
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 40,
                  ),
                  alignment: Alignment.center,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    runAlignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      LemmaMeaningWidget(
                        constructUse: token.vocabConstructID.constructUses,
                        langCode: MatrixState.pangeaController
                                .languageController.userL2?.langCodeShort ??
                            LanguageKeys.defaultLanguage,
                        token: overlayController.selectedToken!,
                        controller: overlayController,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 8.0,
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!_selectedToken.doesLemmaTextMatchTokenText) ...[
                      Text(
                        _selectedToken.text.content,
                        style: Theme.of(context).textTheme.bodyLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      WordAudioButton(
                        text: _selectedToken.text.content,
                        isSelected: MessageMode.messageTextToSpeech ==
                            overlayController.toolbarMode,
                        baseOpacity: 0.4,
                      ),
                    ],
                    ..._selectedToken.sortedMorphs.map(
                      (featureTagPair) => MorphologicalListItem(
                        morphFeature: featureTagPair.key,
                        morphTag: featureTagPair.value,
                        wordForm: token.text.content,
                        overlayController: overlayController,
                      ),
                    ),
                  ],
                ),
                // if (_selectedMorphFeature != null)
                //   MorphologicalCenterWidget(
                //     token: token,
                //     morphFeature: _selectedMorphFeature!,
                //     pangeaMessageEvent: messageEvent,
                //     overlayController: overlayController,
                //     onEditDone: onEditDone,
                //   ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
