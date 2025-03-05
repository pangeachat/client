import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/emoji_practice_button.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/word_text_with_audio_button.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/lemma_meaning_widget.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/lemma_widget.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/morphs/morphological_list_item.dart';
import 'package:flutter/material.dart';

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

  MessageMode get _mode => overlayController.toolbarMode;

  String? get _selectedMorphFeature => overlayController.selectedMorphFeature;

  void onEditDone() => overlayController.initializeTokensAndMode();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppConfig.toolbarMinHeight,
        maxHeight: AppConfig.toolbarMaxHeight,
        maxWidth: AppConfig.toolbarMinWidth,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          // crossAxisAlignment: CrossAxisAlignment.stretch,
          // spacing: 4.0,
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  EmojiPracticeButton(
                    token: _selectedToken,
                    onPressed: () => overlayController.updateToolbarMode(
                      MessageMode.wordEmoji,
                    ),
                    isSelected: _mode == MessageMode.wordEmoji,
                  ),
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
                  ),
                ],
              ),
            ),
            // const SizedBox(
            //   height: 4.0,
            // ),
            LemmaMeaningWidget(
              token: token,
              langCode: messageEvent.messageDisplayLangCode,
              controller: overlayController,
            ),
            const SizedBox(
              height: 16.0,
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
              if (!_selectedToken.doesLemmaTextMatchTokenText)
                WordTextWithAudioButton(
                text: _selectedToken.text.content,
                ttsController: tts,
                textSize: Theme.of(context).textTheme.titleMedium?.fontSize,
                ),
              ..._selectedToken.sortedMorphs.map((featureTagPair) => MorphologicalListItem(
                  onPressed: (feature) =>
                  overlayController.updateToolbarMode(
                MessageMode.wordMorph,
                feature,
                ),
            morphFeature: featureTagPair.key,
            morphTag: featureTagPair.value,
            isUnlocked: !overlayController.pangeaMessageEvent!.shouldDoActivity(
              token: token,
              a: ActivityTypeEnum.morphId,
              feature: featureTagPair.key,
              tag: featureTagPair.value,
            ),
            isSelected: _selectedMorphFeature == featureTagPair.key,
            ),),
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
    );
  }
}
