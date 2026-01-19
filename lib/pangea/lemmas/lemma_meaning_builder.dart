import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaMeaningBuilder extends StatefulWidget {
  final String langCode;
  final ConstructIdentifier constructId;
  final Map<String, dynamic> messageInfo;
  final ValueNotifier<int>? reloadNotifier;

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
    this.reloadNotifier,
  });

  @override
  LemmaMeaningBuilderState createState() => LemmaMeaningBuilderState();
}

class LemmaMeaningBuilderState extends State<LemmaMeaningBuilder> {
  final ValueNotifier<AsyncState<LemmaInfoResponse>> _loader =
      ValueNotifier(const AsyncState.idle());

  @override
  void initState() {
    super.initState();
    _load();
    widget.reloadNotifier?.addListener(_load);
  }

  @override
  void didUpdateWidget(covariant LemmaMeaningBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.constructId != widget.constructId ||
        oldWidget.langCode != widget.langCode) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.reloadNotifier?.removeListener(_load);
    _loader.dispose();
    super.dispose();
  }

  AsyncState<LemmaInfoResponse> get state => _loader.value;
  bool get isError => _loader.value is AsyncError;
  bool get isLoaded => _loader.value is AsyncLoaded;
  LemmaInfoResponse? get lemmaInfo =>
      isLoaded ? (_loader.value as AsyncLoaded<LemmaInfoResponse>).value : null;

  LemmaInfoRequest get _request => LemmaInfoRequest(
        lemma: widget.constructId.lemma,
        partOfSpeech: widget.constructId.category,
        lemmaLang: widget.langCode,
        userL1: MatrixState.pangeaController.userController.userL1?.langCode ??
            LanguageKeys.defaultLanguage,
        messageInfo: widget.messageInfo,
      );

  Future<void> _load() async {
    _loader.value = const AsyncState.loading();
    final result = await LemmaInfoRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      _request,
    );

    if (!mounted) return;
    result.isError
        ? _loader.value = AsyncState.error(result.asError!.error)
        : _loader.value = AsyncState.loaded(result.asValue!.value);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _loader,
      builder: (context, _, __) => widget.builder(
        context,
        this,
      ),
    );
  }
}
