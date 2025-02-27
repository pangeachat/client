import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/reading_assistance_input_bar_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/emoji_practice_button.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/word_text_with_audio_button.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/lemma_meaning_widget.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/lemma_widget.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/morphs/morphological_center_widget.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/morphs/morphological_list_widget.dart';
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

  ReadingAssistanceModeEnum get _mode => overlayController.inputBarMode;

  String? get _selectedMorphFeature => overlayController.selectedMorphFeature;

  void onEditDone() => overlayController.initializeTokensAndMode();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppConfig.toolbarMinHeight,
        maxHeight: AppConfig.toolbarMaxHeight,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppConfig.toolbarMinHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
                  EmojiPracticeButton(
                    token: _selectedToken,
                    onPressed: () => overlayController.updateInputBarMode(
                      ReadingAssistanceModeEnum.wordEmojiChoice,
                    ),
                    isSelected:
                        _mode == ReadingAssistanceModeEnum.wordEmojiChoice,
                  ),
                  LemmaMeaningWidget(
                    token: token,
                    langCode: messageEvent.messageDisplayLangCode,
                    controller: overlayController,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      if (!_selectedToken.doesLemmaTextMatchTokenText)
                        WordTextWithAudioButton(
                          text: _selectedToken.text.content,
                          ttsController: tts,
                        ),
                      MorphologicalListWidget(
                        pangeaMessageEvent: messageEvent,
                        token: token,
                        setMorphFeature: (feature) =>
                            overlayController.updateInputBarMode(
                          ReadingAssistanceModeEnum.morph,
                          feature: feature,
                        ),
                        selectedMorphFeature: _selectedMorphFeature,
                      ),
                    ],
                  ),
                  if (_selectedMorphFeature != null)
                    MorphologicalCenterWidget(
                      token: token,
                      morphFeature: _selectedMorphFeature!,
                      pangeaMessageEvent: messageEvent,
                      overlayController: overlayController,
                      onEditDone: onEditDone,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
