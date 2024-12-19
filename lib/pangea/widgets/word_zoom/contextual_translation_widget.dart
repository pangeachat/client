import 'package:fluffychat/pangea/constants/language_constants.dart';
import 'package:fluffychat/pangea/enum/activity_type_enum.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/repo/full_text_translation_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class ContextualTranslationWidget extends StatefulWidget {
  final PangeaToken token;
  final String fullText;
  final String langCode;

  const ContextualTranslationWidget({
    super.key,
    required this.token,
    required this.fullText,
    required this.langCode,
  });

  @override
  _ContextualTranslationWidgetState createState() =>
      _ContextualTranslationWidgetState();
}

class _ContextualTranslationWidgetState
    extends State<ContextualTranslationWidget> {
  late Future<String> _definition;

  // TODO - if shouldDoActivity is true, show translation icon and onClick, show practice activity

  // if token has changed, update the definition
  @override
  void didUpdateWidget(covariant ContextualTranslationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.token != oldWidget.token) {
      setState(() {
        _definition = _fetchDefinition();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _definition = _fetchDefinition();
  }

  Future<String> _fetchDefinition() async {
    if (widget.token.shouldDoActivity(
      a: ActivityTypeEnum.wordMeaning,
      feature: null,
      tag: null,
    )) {
      return '?';
    } else {
      final FullTextTranslationResponseModel response =
          await FullTextTranslationRepo.translate(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        request: FullTextTranslationRequestModel(
          text: widget.fullText,
          tgtLang: MatrixState
                  .pangeaController.languageController.userL1?.langCode ??
              LanguageKeys.defaultLanguage,
          userL2: MatrixState
                  .pangeaController.languageController.userL2?.langCode ??
              LanguageKeys.defaultLanguage,
          userL1: MatrixState
                  .pangeaController.languageController.userL1?.langCode ??
              LanguageKeys.defaultLanguage,
          offset: widget.token.text.offset,
          length: widget.token.text.length,
          deepL: false,
        ),
      );
      return response.bestTranslation;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _definition,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return ActionChip(
            avatar: const Icon(Icons.translate),
            label: Text(snapshot.data ?? 'No definition found'),
            onPressed: () {
              // Handle chip click
            },
          );
        }
      },
    );
  }
}
