import 'package:fluffychat/pangea/enum/instructions_enum.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/models/representation_content_model.dart';
import 'package:fluffychat/pangea/repo/full_text_translation_repo.dart';
import 'package:fluffychat/pangea/utils/bot_style.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/utils/inline_tooltip.dart';
import 'package:fluffychat/pangea/widgets/chat/message_toolbar.dart';
import 'package:fluffychat/pangea/widgets/chat/toolbar_content_loading_indicator.dart';
import 'package:fluffychat/pangea/widgets/igc/card_error_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class MessageTranslationCard extends StatefulWidget {
  final PangeaMessageEvent messageEvent;
  final PangeaTokenText? selection;

  const MessageTranslationCard({
    super.key,
    required this.messageEvent,
    required this.selection,
  });

  @override
  MessageTranslationCardState createState() => MessageTranslationCardState();
}

class MessageTranslationCardState extends State<MessageTranslationCard> {
  PangeaRepresentation? repEvent;
  String? selectionTranslation;
  bool _fetchingTranslation = false;

  @override
  void initState() {
    debugPrint('MessageTranslationCard initState');
    super.initState();
    loadTranslation();
  }

  @override
  void didUpdateWidget(covariant MessageTranslationCard oldWidget) {
    if (oldWidget.selection != widget.selection) {
      debugPrint('selection changed');
      loadTranslation();
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> fetchRepresentationText() async {
    if (l1Code == null) return;

    repEvent = widget.messageEvent
        .representationByLanguage(
          l1Code!,
        )
        ?.content;

    if (repEvent == null && mounted) {
      repEvent = await widget.messageEvent.representationByLanguageGlobal(
        langCode: l1Code!,
      );
    }
  }

  Future<void> fetchSelectedTextTranslation() async {
    if (!mounted) return;

    final pangeaController = MatrixState.pangeaController;

    if (!pangeaController.languageController.languagesSet) {
      selectionTranslation = widget.messageEvent.messageDisplayText;
      return;
    }

    final FullTextTranslationResponseModel res =
        await FullTextTranslationRepo.translate(
      accessToken: pangeaController.userController.accessToken,
      request: FullTextTranslationRequestModel(
        text: widget.messageEvent.messageDisplayText,
        srcLang: widget.messageEvent.messageDisplayLangCode,
        tgtLang: l1Code!,
        offset: widget.selection?.offset,
        length: widget.selection?.length,
        userL1: l1Code!,
        userL2: l2Code!,
      ),
    );

    selectionTranslation = res.translations.first;
  }

  Future<void> loadTranslation() async {
    if (!mounted) return;

    setState(() => _fetchingTranslation = true);

    try {
      await (widget.selection != null
          ? fetchSelectedTextTranslation()
          : fetchRepresentationText());
    } catch (err) {
      ErrorHandler.logError(e: err);
    }

    if (mounted) {
      setState(() => _fetchingTranslation = false);
    }
  }

  String? get l1Code =>
      MatrixState.pangeaController.languageController.activeL1Code();
  String? get l2Code =>
      MatrixState.pangeaController.languageController.activeL2Code();

  /// Show warning if message's language code is user's L1
  /// or if translated text is same as original text.
  /// Warning does not show if was previously closed
  bool get notGoingToTranslate {
    final bool isWrittenInL1 =
        l1Code != null && widget.messageEvent.originalSent?.langCode == l1Code;
    final bool isTextIdentical = selectionTranslation != null &&
        widget.messageEvent.originalSent?.text == selectionTranslation;

    return (isWrittenInL1 || isTextIdentical);
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MessageTranslationCard build');
    if (!_fetchingTranslation &&
        repEvent == null &&
        selectionTranslation == null) {
      return const CardErrorWidget();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minHeight: minCardHeight),
      alignment: Alignment.center,
      child: _fetchingTranslation
          ? const ToolbarContentLoadingIndicator()
          : Column(
              children: [
                widget.selection != null
                    ? Text(
                        selectionTranslation!,
                        style: BotStyle.text(context),
                      )
                    : Text(
                        repEvent!.text,
                        style: BotStyle.text(context),
                      ),
                if (notGoingToTranslate && widget.selection == null)
                  InlineTooltip(
                    instructionsEnum: InstructionsEnum.l1Translation,
                    onClose: () => setState(() {}),
                  ),
                if (widget.selection != null)
                  InlineTooltip(
                    instructionsEnum: InstructionsEnum.clickAgainToDeselect,
                    onClose: () => setState(() {}),
                  ),
                // if (widget.selection != null)
              ],
            ),
    );
  }
}
