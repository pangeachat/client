import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/repo/full_text_translation_repo.dart';
import 'package:fluffychat/pangea/widgets/chat/tts_controller.dart';
import 'package:fluffychat/pangea/widgets/igc/word_data_card.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class WordDetailsCard extends StatefulWidget {
  final PangeaTokenText selectedSpan;
  final PangeaMessageEvent pangeaMessageEvent;
  final TtsController tts;

  const WordDetailsCard({
    super.key,
    required this.selectedSpan,
    required this.pangeaMessageEvent,
    required this.tts,
  });

  @override
  WordDetailsCardState createState() => WordDetailsCardState();
}

class WordDetailsCardState extends State<WordDetailsCard> {
  String? _selectionTranslation;

  @override
  void initState() {
    super.initState();
    _fetchSelectedTextTranslation();
  }

  @override
  void didUpdateWidget(covariant WordDetailsCard oldWidget) {
    if (oldWidget.selectedSpan != widget.selectedSpan) {
      setState(() => _selectionTranslation = null);
      _fetchSelectedTextTranslation();
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _fetchSelectedTextTranslation() async {
    if (!mounted) return;

    final pangeaController = MatrixState.pangeaController;

    if (!pangeaController.languageController.languagesSet) {
      _selectionTranslation = null;
      return;
    }

    final l1Code = pangeaController.languageController.userL1!.langCode;
    final l2Code = pangeaController.languageController.userL2!.langCode;

    final FullTextTranslationResponseModel res =
        await FullTextTranslationRepo.translate(
      accessToken: pangeaController.userController.accessToken,
      request: FullTextTranslationRequestModel(
        text: widget.pangeaMessageEvent.messageDisplayText,
        srcLang: widget.pangeaMessageEvent.messageDisplayLangCode,
        tgtLang: l1Code,
        offset: widget.selectedSpan.offset,
        length: widget.selectedSpan.length,
        userL1: l1Code,
        userL2: l2Code,
      ),
    );

    _selectionTranslation = res.translations.first;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppConfig.toolbarMinWidth,
        maxHeight: AppConfig.toolbarMaxHeight,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {
                      widget.tts.tryToSpeak(
                        widget.selectedSpan.content,
                        context,
                        widget.pangeaMessageEvent.eventId,
                      );
                    },
                  ),
                  Text(widget.selectedSpan.content),
                  const Text(" : "),
                  Text(_selectionTranslation ?? ''),
                ],
              ),
              WordDataCard(
                word: widget.selectedSpan.content,
                wordLang: widget.pangeaMessageEvent.messageDisplayLangCode,
                fullText: widget.pangeaMessageEvent.messageDisplayText,
                fullTextLang: widget.pangeaMessageEvent.messageDisplayLangCode,
                hasInfo: true,
                room: widget.pangeaMessageEvent.room,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
