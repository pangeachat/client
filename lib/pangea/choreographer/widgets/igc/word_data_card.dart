import 'package:flutter/material.dart';

import 'package:http/http.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/choreographer/repo/contextual_definition_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/contextual_definition_request_model.dart';
import 'package:fluffychat/pangea/choreographer/repo/contextual_definition_response_model.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/toolbar/widgets/toolbar_content_loading_indicator.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'card_error_widget.dart';

class WordDataCard extends StatefulWidget {
  final String word;
  final String fullText;
  final String? choiceFeedback;
  final String wordLang;
  final String fullTextLang;

  const WordDataCard({
    super.key,
    required this.word,
    required this.fullText,
    this.choiceFeedback,
    required this.wordLang,
    required this.fullTextLang,
  });

  @override
  State<WordDataCard> createState() => WordDataCardController();
}

class WordDataCardController extends State<WordDataCard> {
  final PangeaController controller = MatrixState.pangeaController;

  bool isLoadingContextualDefinition = false;
  ContextualDefinitionResponseModel? contextualDefinitionRes;

  Object? definitionError;
  LanguageModel? activeL1;
  LanguageModel? activeL2;

  Response get noLanguages => Response("", 405);

  @override
  void initState() {
    if (!mounted) return;
    activeL1 = controller.languageController.activeL1Model()!;
    activeL2 = controller.languageController.activeL2Model()!;
    if (activeL1 == null || activeL2 == null) {
      definitionError = noLanguages;
    } else {
      getContextualDefinition();
    }
    super.initState();
  }

  @override
  void didUpdateWidget(covariant WordDataCard oldWidget) {
    // debugger(when: kDebugMode);
    if (oldWidget.word != widget.word) {
      getContextualDefinition();
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> getContextualDefinition() async {
    final ContextualDefinitionRequestModel req =
        ContextualDefinitionRequestModel(
      fullText: widget.fullText,
      word: widget.word,
      feedbackLang: activeL1?.langCode ?? LanguageKeys.defaultLanguage,
      fullTextLang: widget.fullTextLang,
      wordLang: widget.wordLang,
    );
    if (!mounted) return;

    setState(() {
      contextualDefinitionRes = null;
      definitionError = null;
      isLoadingContextualDefinition = true;
    });

    final resp = await ContextualDefinitionRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      req,
    );

    if (resp.isError) {
      definitionError = Exception("Error getting definition");
    }

    if (mounted) {
      setState(() => isLoadingContextualDefinition = false);
    }
  }

  void handleGetDefinitionButtonPress() {
    if (isLoadingContextualDefinition) return;
    getContextualDefinition();
  }

  @override
  Widget build(BuildContext context) => WordDataCardView(controller: this);
}

class WordDataCardView extends StatelessWidget {
  const WordDataCardView({
    super.key,
    required this.controller,
  });

  final WordDataCardController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.activeL1 == null || controller.activeL2 == null) {
      ErrorHandler.logError(
        m: "should not be here",
        data: {
          "activeL1": controller.activeL1?.toJson(),
          "activeL2": controller.activeL2?.toJson(),
        },
      );
      return CardErrorWidget(
        error: L10n.of(context).noLanguagesSet,
        maxWidth: AppConfig.toolbarMinWidth,
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppConfig.toolbarMinWidth,
        maxHeight: AppConfig.toolbarMaxHeight,
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                if (controller.widget.choiceFeedback != null)
                  Text(
                    controller.widget.choiceFeedback!,
                    style: BotStyle.text(context),
                  ),
                const SizedBox(height: 5.0),
                if (controller.isLoadingContextualDefinition)
                  const ToolbarContentLoadingIndicator(),
                if (controller.contextualDefinitionRes != null)
                  Text(
                    controller.contextualDefinitionRes!.text,
                    style: BotStyle.text(context),
                    textAlign: TextAlign.center,
                  ),
                if (controller.definitionError != null)
                  Text(
                    L10n.of(context).sorryNoResults,
                    style: BotStyle.text(context),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
