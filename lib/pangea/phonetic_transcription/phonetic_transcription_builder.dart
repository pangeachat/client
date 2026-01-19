import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/languages/language_arc_model.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_request.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'phonetic_transcription_repo.dart';

class PhoneticTranscriptionBuilder extends StatefulWidget {
  final LanguageModel textLanguage;
  final String text;
  final ValueNotifier<int>? reloadNotifier;

  final Widget Function(
    BuildContext context,
    PhoneticTranscriptionBuilderState controller,
  ) builder;

  const PhoneticTranscriptionBuilder({
    super.key,
    required this.textLanguage,
    required this.text,
    required this.builder,
    this.reloadNotifier,
  });

  @override
  PhoneticTranscriptionBuilderState createState() =>
      PhoneticTranscriptionBuilderState();
}

class PhoneticTranscriptionBuilderState
    extends State<PhoneticTranscriptionBuilder> {
  final ValueNotifier<AsyncState<String>> _loader =
      ValueNotifier(const AsyncState.idle());

  @override
  void initState() {
    super.initState();
    _load();
    widget.reloadNotifier?.addListener(_load);
  }

  @override
  void didUpdateWidget(covariant PhoneticTranscriptionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.textLanguage != widget.textLanguage) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.reloadNotifier?.removeListener(_load);
    _loader.dispose();
    super.dispose();
  }

  AsyncState<String> get state => _loader.value;
  bool get isError => _loader.value is AsyncError;
  bool get isLoaded => _loader.value is AsyncLoaded;
  String? get transcription =>
      isLoaded ? (_loader.value as AsyncLoaded<String>).value : null;

  PhoneticTranscriptionRequest get _request => PhoneticTranscriptionRequest(
        arc: LanguageArc(
          l1: MatrixState.pangeaController.userController.userL1!,
          l2: widget.textLanguage,
        ),
        content: PangeaTokenText.fromString(widget.text),
      );

  Future<void> _load() async {
    _loader.value = const AsyncState.loading();
    final resp = await PhoneticTranscriptionRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      _request,
    );

    if (!mounted) return;
    resp.isError
        ? _loader.value = AsyncState.error(resp.asError!.error)
        : _loader.value = AsyncState.loaded(
            resp.asValue!.value.phoneticTranscriptionResult
                .phoneticTranscription.first.phoneticL1Transcription.content,
          );
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
