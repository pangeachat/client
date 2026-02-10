import 'package:flutter/material.dart';

import 'package:async/async.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/choreographer/it/contextual_definition_repo.dart';
import 'package:fluffychat/pangea/choreographer/it/contextual_definition_request_model.dart';
import 'package:fluffychat/pangea/common/widgets/content_loading_indicator.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class WordDataCard extends StatelessWidget {
  final String word;
  final String fullText;
  final String langCode;

  const WordDataCard({
    super.key,
    required this.word,
    required this.fullText,
    required this.langCode,
  });

  ContextualDefinitionRequestModel get _request =>
      ContextualDefinitionRequestModel(
        fullText: fullText,
        word: word,
        fullTextLang: langCode,
        wordLang: langCode,
        feedbackLang:
            MatrixState.pangeaController.userController.userL1Code ??
            LanguageKeys.defaultLanguage,
      );

  Future<Result<String>> _fetchDefinition() {
    return ContextualDefinitionRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      _request,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => Result.error("Timeout getting definition"),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FutureBuilder<Result<String>>(
        future: _fetchDefinition(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const ContentLoadingIndicator();
          }
          final result = snapshot.data!;
          if (result.isError) {
            return Text(
              L10n.of(context).sorryNoResults,
              style: BotStyle.text(context),
              textAlign: TextAlign.center,
            );
          }
          return Text(result.result!, style: BotStyle.text(context));
        },
      ),
    );
  }
}
