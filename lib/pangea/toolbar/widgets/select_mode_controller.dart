import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/pangea/toolbar/models/speech_to_text_models.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_audio_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/select_mode_buttons.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SelectModeController {
  final PangeaMessageEvent messageEvent;

  SelectModeController(
    this.messageEvent,
  );

  ValueNotifier<SelectMode?> selectedMode = ValueNotifier<SelectMode?>(null);

  final ValueNotifier<AsyncState<SpeechToTextModel>> transcriptionState =
      ValueNotifier<AsyncState<SpeechToTextModel>>(const AsyncState.idle());

  final ValueNotifier<AsyncState<String>> translationState =
      ValueNotifier<AsyncState<String>>(const AsyncState.idle());

  final ValueNotifier<AsyncState<String>> speechTranslationState =
      ValueNotifier<AsyncState<String>>(const AsyncState.idle());

  final ValueNotifier<AsyncState<(PangeaAudioFile, File?)>> audioState =
      ValueNotifier<AsyncState<(PangeaAudioFile, File?)>>(
    const AsyncState.idle(),
  );

  final StreamController contentChangedStream = StreamController.broadcast();

  bool _disposed = false;

  bool get showingExtraContent =>
      (selectedMode.value == SelectMode.translate &&
          translationState.value is AsyncLoaded) ||
      (selectedMode.value == SelectMode.speechTranslation &&
          speechTranslationState.value is AsyncLoaded) ||
      transcriptionState.value is AsyncLoaded ||
      transcriptionState.value is AsyncError;

  String? get l1Code =>
      MatrixState.pangeaController.languageController.userL1?.langCodeShort;
  String? get l2Code =>
      MatrixState.pangeaController.languageController.userL2?.langCodeShort;

  (PangeaAudioFile, File?)? get audioFile => audioState.value is AsyncLoaded
      ? (audioState.value as AsyncLoaded<(PangeaAudioFile, File?)>).value
      : null;

  ValueNotifier<AsyncState>? modeStateNotifier(SelectMode mode) {
    switch (mode) {
      case SelectMode.audio:
        return audioState;
      case SelectMode.translate:
        return translationState;
      case SelectMode.speechTranslation:
        return speechTranslationState;
      default:
        return null;
    }
  }

  ValueNotifier<AsyncState>? get currentModeStateNotifier {
    final mode = selectedMode.value;
    if (mode == null) return null;
    return modeStateNotifier(mode);
  }

  void dispose() {
    selectedMode.dispose();
    transcriptionState.dispose();
    translationState.dispose();
    speechTranslationState.dispose();
    audioState.dispose();
    contentChangedStream.close();
    _disposed = true;
  }

  void setSelectMode(SelectMode? mode) {
    if (selectedMode.value == mode) return;
    selectedMode.value = mode;
  }

  Future<void> fetchAudio() async {
    audioState.value = const AsyncState.loading();
    try {
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
      if (_disposed) return;
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

      audioState.value = AsyncState.loaded((audioBytes, audioFile));
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        m: 'something wrong getting audio in MessageAudioCardState',
        data: {
          'widget.messageEvent.messageDisplayLangCode':
              messageEvent.messageDisplayLangCode,
        },
      );
      if (_disposed) return;
      audioState.value = AsyncState.error(e);
    }
  }

  Future<void> fetchTranslation() async {
    if (l1Code == null ||
        translationState.value is AsyncLoading ||
        translationState.value is AsyncLoaded) {
      return;
    }

    try {
      translationState.value = const AsyncState.loading();
      final rep = await messageEvent.l1Respresentation();
      if (_disposed) return;
      translationState.value = AsyncState.loaded(rep.text);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        m: 'Error fetching translation',
        data: {
          'l1Code': l1Code,
          'messageEvent': messageEvent.event.toJson(),
        },
      );
      if (_disposed) return;
      translationState.value = AsyncState.error(e);
    }
  }

  Future<void> fetchTranscription() async {
    try {
      if (transcriptionState.value is AsyncLoading ||
          transcriptionState.value is AsyncLoaded) {
        // If a transcription is already in progress or finished, don't fetch again
        return;
      }

      if (l1Code == null) {
        transcriptionState.value = const AsyncState.error(
          'Language code or message event is null',
        );
        return;
      }

      final resp = await messageEvent.getSpeechToText(
        l1Code!,
        l2Code!,
      );

      if (_disposed) return;
      if (resp == null) {
        transcriptionState.value = const AsyncState.error(
          'Transcription response is null',
        );
        return;
      }
      transcriptionState.value = AsyncState.loaded(resp);
    } catch (err, s) {
      ErrorHandler.logError(
        e: err,
        s: s,
        data: {},
      );
      if (_disposed) return;
      transcriptionState.value = AsyncState.error(err);
    }
  }

  Future<void> fetchSpeechTranslation() async {
    if (l1Code == null ||
        l2Code == null ||
        speechTranslationState.value is AsyncLoading ||
        speechTranslationState.value is AsyncLoaded ||
        transcriptionState.value is AsyncError) {
      return;
    }

    try {
      speechTranslationState.value = const AsyncState.loading();

      if (transcriptionState.value is AsyncIdle ||
          transcriptionState.value is AsyncLoading) {
        await fetchTranscription();
        if (_disposed) return;
        if (transcriptionState.value is! AsyncLoaded) {
          throw Exception('Transcription is null');
        }
      }

      final translation = await messageEvent.sttTranslationByLanguageGlobal(
        langCode: l1Code!,
        l1Code: l1Code!,
        l2Code: l2Code!,
      );
      if (translation == null) {
        throw Exception('Translation is null');
      }

      if (_disposed) return;
      speechTranslationState.value = AsyncState.loaded(translation.translation);
    } catch (err, s) {
      ErrorHandler.logError(
        e: err,
        s: s,
        data: {},
      );
      if (_disposed) return;
      speechTranslationState.value = AsyncState.error(err);
    }
  }

  bool get isError {
    switch (selectedMode.value) {
      case SelectMode.audio:
        return audioState.value is AsyncError;
      case SelectMode.translate:
        return translationState.value is AsyncError;
      case SelectMode.speechTranslation:
        return speechTranslationState.value is AsyncError;
      default:
        return false;
    }
  }

  bool get isLoading {
    switch (selectedMode.value) {
      case SelectMode.audio:
        return audioState.value is AsyncLoading;
      case SelectMode.translate:
        return translationState.value is AsyncLoading;
      case SelectMode.speechTranslation:
        return speechTranslationState.value is AsyncLoading;
      default:
        return false;
    }
  }
}
