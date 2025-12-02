import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/pangea/toolbar/models/speech_to_text_models.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_audio_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/select_mode_buttons.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _TranscriptionLoader extends AsyncLoader<SpeechToTextModel> {
  final PangeaMessageEvent messageEvent;
  _TranscriptionLoader(this.messageEvent) : super();

  @override
  Future<SpeechToTextModel> fetch() => messageEvent.getSpeechToText(
        MatrixState.pangeaController.languageController.userL1!.langCodeShort,
        MatrixState.pangeaController.languageController.userL2!.langCodeShort,
      );
}

class _STTTranslationLoader extends AsyncLoader<String> {
  final PangeaMessageEvent messageEvent;
  _STTTranslationLoader(this.messageEvent) : super();

  @override
  Future<String> fetch() => messageEvent.sttTranslationByLanguageGlobal(
        langCode: MatrixState
            .pangeaController.languageController.userL1!.langCodeShort,
        l1Code: MatrixState
            .pangeaController.languageController.userL1!.langCodeShort,
        l2Code: MatrixState
            .pangeaController.languageController.userL2!.langCodeShort,
      );
}

class _TranslationLoader extends AsyncLoader<String> {
  final PangeaMessageEvent messageEvent;
  _TranslationLoader(this.messageEvent) : super();

  @override
  Future<String> fetch() => messageEvent.l1Respresentation();
}

class _AudioLoader extends AsyncLoader<(PangeaAudioFile, File?)> {
  final PangeaMessageEvent messageEvent;
  _AudioLoader(this.messageEvent) : super();

  @override
  Future<(PangeaAudioFile, File?)> fetch() async {
    final String langCode = messageEvent.messageDisplayLangCode;

    final Event? localEvent = messageEvent.getTextToSpeechLocal(
      langCode,
      messageEvent.messageDisplayText,
    );

    PangeaAudioFile? audioBytes;
    if (localEvent != null) {
      audioBytes = await localEvent.getPangeaAudioFile();
    } else {
      audioBytes = await messageEvent.getMatrixAudioFile(
        langCode,
      );
    }
    if (audioBytes == null) {
      throw Exception('Audio bytes are null');
    }

    File? audioFile;
    if (!kIsWeb) {
      final tempDir = await getTemporaryDirectory();

      File? file;
      file = File('${tempDir.path}/${audioBytes.name}');
      await file.writeAsBytes(audioBytes.bytes);
      audioFile = file;
    }

    return (audioBytes, audioFile);
  }
}

class SelectModeController {
  final PangeaMessageEvent messageEvent;
  final _TranscriptionLoader _transcriptLoader;
  final _TranslationLoader _translationLoader;
  final _AudioLoader _audioLoader;
  final _STTTranslationLoader _sttTranslationLoader;

  SelectModeController(
    this.messageEvent,
  )   : _transcriptLoader = _TranscriptionLoader(messageEvent),
        _translationLoader = _TranslationLoader(messageEvent),
        _audioLoader = _AudioLoader(messageEvent),
        _sttTranslationLoader = _STTTranslationLoader(messageEvent);

  ValueNotifier<SelectMode?> selectedMode = ValueNotifier<SelectMode?>(null);
  final StreamController contentChangedStream = StreamController.broadcast();

  void dispose() {
    selectedMode.dispose();
    _transcriptLoader.dispose();
    _translationLoader.dispose();
    _sttTranslationLoader.dispose();
    _audioLoader.dispose();
    contentChangedStream.close();
  }

  ValueNotifier<AsyncState<String>> get translationState =>
      _translationLoader.state;

  ValueNotifier<AsyncState<SpeechToTextModel>> get transcriptionState =>
      _transcriptLoader.state;

  ValueNotifier<AsyncState<String>> get speechTranslationState =>
      _sttTranslationLoader.state;

  (PangeaAudioFile, File?)? get audioFile => _audioLoader.value;

  bool get isLoading => currentModeStateNotifier?.value is AsyncLoading;

  bool get isShowingExtraContent =>
      (selectedMode.value == SelectMode.translate &&
          _translationLoader.isLoaded) ||
      (selectedMode.value == SelectMode.speechTranslation &&
          _sttTranslationLoader.isLoaded) ||
      _transcriptLoader.isLoaded ||
      _transcriptLoader.isError;

  ValueNotifier<AsyncState>? get currentModeStateNotifier =>
      modeStateNotifier(selectedMode.value);

  ValueNotifier<AsyncState>? modeStateNotifier(SelectMode? mode) =>
      switch (mode) {
        SelectMode.audio => _audioLoader.state,
        SelectMode.translate => _translationLoader.state,
        SelectMode.speechTranslation => _sttTranslationLoader.state,
        _ => null,
      };

  void setSelectMode(SelectMode? mode) {
    if (selectedMode.value == mode) return;
    selectedMode.value = mode;
  }

  Future<void> fetchAudio() => _audioLoader.load();
  Future<void> fetchTranslation() => _translationLoader.load();
  Future<void> fetchTranscription() => _transcriptLoader.load();
  Future<void> fetchSpeechTranslation() => _sttTranslationLoader.load();
}
