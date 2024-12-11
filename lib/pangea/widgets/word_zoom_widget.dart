import 'package:flutter/material.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/widgets/practice_activity/word_audio_button.dart';
import 'package:fluffychat/pangea/widgets/contextual_translation_widget.dart';
import 'package:fluffychat/pangea/widgets/morphological_widget.dart';
import 'package:fluffychat/pangea/widgets/lemma_widget.dart';
import 'package:fluffychat/pangea/widgets/part_of_speech_widget.dart';
import 'package:fluffychat/pangea/widgets/lemma_definition_widget.dart';

class WordZoomWidget extends StatefulWidget {
  final PangeaToken token;

  const WordZoomWidget({Key? key, required this.token}) : super(key: key);

  @override
  _WordZoomWidgetState createState() => _WordZoomWidgetState();
}

class _WordZoomWidgetState extends State<WordZoomWidget> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(widget.token.text.content),
          WordAudioButton(
            text: widget.token.text.content,
            ttsController: TtsController(),
            eventID: 'eventID', // Replace with actual event ID
          ),
          ContextualTranslationWidget(token: widget.token),
          Wrap(
            children: widget.token.morph.entries
                .map((entry) => MorphologicalWidget(
                      token: widget.token,
                      morphFeature: entry.key,
                      morphValue: entry.value,
                    ))
                .toList(),
          ),
          Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LemmaWidget(token: widget.token),
              PartOfSpeechWidget(token: widget.token),
              LemmaProgressWidget(token: widget.token),
            ],
          ),
          LemmaDefinitionWidget(token: widget.token),
        ],
      ),
    );
  }
}
