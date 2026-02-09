import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Fetches and exposes the v2 [PTResponse] for a given surface text.
///
/// Exposes both the [PTRequest] used and the full [PTResponse] received,
/// which callers need for token feedback and disambiguation.
class PhoneticTranscriptionBuilder extends StatefulWidget {
  final String langCode;
  final String text;
  final ValueNotifier<int>? reloadNotifier;

  final Widget Function(
    BuildContext context,
    PhoneticTranscriptionBuilderState controller,
  ) builder;

  const PhoneticTranscriptionBuilder({
    super.key,
    required this.langCode,
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
  final ValueNotifier<AsyncState<PTResponse>> _loader =
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

  AsyncState<PTResponse> get state => _loader.value;
  bool get isError => _loader.value is AsyncError;
  bool get isLoaded => _loader.value is AsyncLoaded;

  /// The full v2 response (for feedback and disambiguation).
  PTResponse? get ptResponse =>
      isLoaded ? (_loader.value as AsyncLoaded<PTResponse>).value : null;

  /// The request that was used to fetch this response.
  PTRequest get ptRequest => _request;

  /// Convenience: the first transcription string (for simple display).
  String? get transcription => ptResponse?.pronunciations.firstOrNull?.transcription;

  PTRequest get _request => PTRequest(
        surface: widget.text,
        langCode: widget.langCode,
        userL1: MatrixState.pangeaController.userController.userL1Code ?? 'en',
        userL2: MatrixState.pangeaController.userController.userL2Code ?? 'en',
      );

  Future<void> _load() async {
    _loader.value = const AsyncState.loading();
    final resp = await PTV2Repo.get(
      MatrixState.pangeaController.userController.accessToken,
      _request,
    );

    if (!mounted) return;
    resp.isError
        ? _loader.value = AsyncState.error(resp.asError!.error)
        : _loader.value = AsyncState.loaded(resp.asValue!.value);
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
