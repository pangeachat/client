import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _LemmaMeaningLoader extends AsyncLoader<LemmaInfoResponse> {
  final LemmaInfoRequest request;
  _LemmaMeaningLoader(this.request) : super();

  @override
  Future<LemmaInfoResponse> fetch() async {
    final result = await LemmaInfoRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      request,
    );

    if (result.isError) {
      throw result.asError!.error;
    }

    return result.asValue!.value;
  }
}

class LemmaMeaningBuilder extends StatefulWidget {
  final String langCode;
  final ConstructIdentifier constructId;
  final Map<String, dynamic> messageInfo;

  final Widget Function(
    BuildContext context,
    LemmaMeaningBuilderState controller,
  ) builder;

  const LemmaMeaningBuilder({
    super.key,
    required this.langCode,
    required this.constructId,
    required this.builder,
    required this.messageInfo,
  });

  @override
  LemmaMeaningBuilderState createState() => LemmaMeaningBuilderState();
}

class LemmaMeaningBuilderState extends State<LemmaMeaningBuilder> {
  late _LemmaMeaningLoader _loader;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant LemmaMeaningBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.constructId != widget.constructId ||
        oldWidget.langCode != widget.langCode) {
      _loader.dispose();
      _reload();
    }
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  bool get isLoading => _loader.isLoading;
  bool get isError => _loader.isError;

  Object? get error =>
      isError ? (_loader.state.value as AsyncError).error : null;

  LemmaInfoResponse? get lemmaInfo => _loader.value;

  LemmaInfoRequest get _request => LemmaInfoRequest(
        lemma: widget.constructId.lemma,
        partOfSpeech: widget.constructId.category,
        lemmaLang: widget.langCode,
        userL1: MatrixState.pangeaController.userController.userL1?.langCode ??
            LanguageKeys.defaultLanguage,
        messageInfo: widget.messageInfo,
      );

  void _reload() {
    _loader = _LemmaMeaningLoader(_request);
    _loader.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _loader.state,
      builder: (context, _, __) => widget.builder(
        context,
        this,
      ),
    );
  }
}
