import 'package:fluffychat/pangea/enum/activity_type_enum.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/widgets/chat/tts_controller.dart';
import 'package:fluffychat/pangea/widgets/practice_activity/word_text_with_audio_button.dart';
import 'package:fluffychat/pangea/widgets/word_zoom/contextual_translation_widget.dart';
import 'package:fluffychat/pangea/widgets/word_zoom/lemma_definition_widget.dart';
import 'package:fluffychat/pangea/widgets/word_zoom/lemma_widget.dart';
import 'package:fluffychat/pangea/widgets/word_zoom/morphological_widget.dart';
import 'package:flutter/material.dart';

enum WordZoomSelection {
  translation,
  emoji,
}

class WordZoomWidget extends StatefulWidget {
  final PangeaToken token;
  final PangeaMessageEvent messageEvent;
  final TtsController tts;

  const WordZoomWidget({
    super.key,
    required this.token,
    required this.messageEvent,
    required this.tts,
  });

  @override
  _WordZoomWidgetState createState() => _WordZoomWidgetState();
}

class _WordZoomWidgetState extends State<WordZoomWidget> {
  ActivityTypeEnum? activityType;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              //TODO create and insert emoji widget
              WordTextWithAudioButton(
                text: widget.token.text.content,
                ttsController: widget.tts,
                eventID: widget.messageEvent.eventId,
              ),
              LemmaWidget(token: widget.token),
            ],
          ),
          ContextualTranslationWidget(
            token: widget.token,
            fullText: widget.messageEvent.messageDisplayText,
            langCode: widget.messageEvent.messageDisplayLangCode,
          ),
          //TODO modify and insert container with modified practice activity card OR translation OR Phonetic based on mode
          MorphologicalListWidget(
            token: widget.token,
          ),
          LemmaDefinitionWidget(
            token: widget.token,
            tokenLang: widget.messageEvent.messageDisplayLangCode,
          ),
        ],
      ),
    );
  }
}
