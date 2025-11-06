import 'package:async/async.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/choreographer/it/contextual_definition_repo.dart';
import 'package:fluffychat/pangea/choreographer/it/contextual_definition_request_model.dart';
import 'package:fluffychat/pangea/common/utils/feedback_model.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/toolbar/widgets/toolbar_content_loading_indicator.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class WordDataCard extends StatefulWidget {
  final String word;
  final String fullText;
  final String wordLang;
  final String fullTextLang;

  const WordDataCard({
    super.key,
    required this.word,
    required this.fullText,
    required this.wordLang,
    required this.fullTextLang,
  });

  @override
  State<WordDataCard> createState() => WordDataCardController();
}

class WordDataCardController extends State<WordDataCard> {
  final FeedbackModel<String> _feedbackModel = FeedbackModel<String>();

  @override
  void initState() {
    super.initState();
    _getContextualDefinition();
  }

  @override
  void didUpdateWidget(covariant WordDataCard oldWidget) {
    if (oldWidget.word != widget.word) {
      _getContextualDefinition();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _feedbackModel.dispose();
    super.dispose();
  }

  ContextualDefinitionRequestModel get _request =>
      ContextualDefinitionRequestModel(
        fullText: widget.fullText,
        word: widget.word,
        fullTextLang: widget.fullTextLang,
        wordLang: widget.wordLang,
        feedbackLang:
            MatrixState.pangeaController.languageController.activeL1Code() ??
                LanguageKeys.defaultLanguage,
      );

  Future<void> _getContextualDefinition() async {
    _feedbackModel.setState(FeedbackLoading<String>());
    final resp = await ContextualDefinitionRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      _request,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        return Result.error("Timeout getting definition");
      },
    );

    if (!mounted) return;
    if (resp.isError) {
      _feedbackModel.setState(
        const FeedbackError<String>("Error getting definition"),
      );
    } else {
      _feedbackModel.setState(FeedbackLoaded<String>(resp.result!.text));
    }
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
          padding: const EdgeInsets.all(20.0),
          child: ListenableBuilder(
            listenable: _feedbackModel,
            builder: (context, _) {
              final state = _feedbackModel.state;
              return switch (state) {
                FeedbackIdle<String>() => const SizedBox.shrink(),
                FeedbackLoading<String>() =>
                  const ToolbarContentLoadingIndicator(),
                FeedbackError<String>() => Text(
                    L10n.of(context).sorryNoResults,
                    style: BotStyle.text(context),
                    textAlign: TextAlign.center,
                  ),
                FeedbackLoaded<String>(:final value) =>
                  Text(value, style: BotStyle.text(context)),
              };
            },
          ),
        ),
      ),
    );
  }
}
