import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/languages/language_arc_model.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_request.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'phonetic_transcription_repo.dart';

class _TranscriptLoader extends AsyncLoader<String> {
  final PhoneticTranscriptionRequest request;
  _TranscriptLoader(this.request) : super();

  @override
  Future<String> fetch() async {
    final resp = await PhoneticTranscriptionRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      request,
    );

    if (resp.isError) {
      throw resp.asError!.error;
    }

    return resp.asValue!.value.phoneticTranscriptionResult.phoneticTranscription
        .first.phoneticL1Transcription.content;
  }
}

class PhoneticTranscriptionBuilder extends StatefulWidget {
  final LanguageModel textLanguage;
  final String text;

  final Widget Function(
    BuildContext context,
    PhoneticTranscriptionBuilderState controller,
  ) builder;

  const PhoneticTranscriptionBuilder({
    super.key,
    required this.textLanguage,
    required this.text,
    required this.builder,
  });

  @override
  PhoneticTranscriptionBuilderState createState() =>
      PhoneticTranscriptionBuilderState();
}

class PhoneticTranscriptionBuilderState
    extends State<PhoneticTranscriptionBuilder> {
  late _TranscriptLoader _loader;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PhoneticTranscriptionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.textLanguage != widget.textLanguage) {
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

  String? get transcription => _loader.value;

  PhoneticTranscriptionRequest get _transcriptRequest =>
      PhoneticTranscriptionRequest(
        arc: LanguageArc(
          l1: MatrixState.pangeaController.userController.userL1!,
          l2: widget.textLanguage,
        ),
        content: PangeaTokenText.fromString(widget.text),
      );

  void _reload() {
    _loader = _TranscriptLoader(_transcriptRequest);
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
