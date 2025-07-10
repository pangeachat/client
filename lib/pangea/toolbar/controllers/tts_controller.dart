import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_tts/flutter_tts.dart' as flutter_tts;
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/audio_player.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_show_popup.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/toolbar/controllers/text_to_speech_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TtsController {
  static void initialize() {
    setAvailableLanguages();
  }

  static List<String> _availableLangCodes = [];

  static final flutter_tts.FlutterTts _tts = flutter_tts.FlutterTts();
  static final StreamController<bool> loadingChoreoStream =
      StreamController<bool>.broadcast();

  static AudioPlayer? audioPlayer;

  static Future<void> _onError(dynamic message) async {
    if (message != 'canceled' && message != 'interrupted') {
      ErrorHandler.logError(
        e: 'TTS error',
        data: {
          'message': message,
        },
      );
    }
  }

  static Future<void> setAvailableLanguages() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _setAvailableBaseLanguages();
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {},
      );
    }
  }

  static Future<void> _setAvailableBaseLanguages() async {
    final voices = (await _tts.getVoices) as List?;
    _availableLangCodes = (voices ?? [])
        .map((v) {
          // on iOS / web, the codes are in 'locale', but on Android, they are in 'name'
          final nameCode = v['name'];
          final localeCode = v['locale'];
          return localeCode.contains("-") ? localeCode : nameCode;
        })
        .toSet()
        .cast<String>()
        .toList();
  }

  static Future<void> _setSpeakingLanguage(String langCode) async {
    String? selectedLangCode;
    final langCodeShort = langCode.split("-").first;
    if (_availableLangCodes.contains(langCode)) {
      selectedLangCode = langCode;
    } else {
      selectedLangCode = _availableLangCodes.firstWhereOrNull(
        (code) => code.startsWith(langCodeShort),
      );
    }

    if (selectedLangCode != null) {
      await (_tts.setLanguage(selectedLangCode));
    } else {
      final jsonData = {
        'langCode': langCode,
        'availableLangCodes': _availableLangCodes,
      };
      debugPrint("TTS: Language not supported: $jsonData");
      Sentry.addBreadcrumb(
        Breadcrumb.fromJson(jsonData),
      );
    }
  }

  static Future<void> stop() async {
    try {
      // return type is dynamic but apparent its supposed to be 1
      // https://pub.dev/packages/flutter_tts
      final result = await (_tts.stop());
      audioPlayer?.stop();

      if (result != 1) {
        ErrorHandler.logError(
          m: 'Unexpected result from tts.stop',
          data: {
            'result': result,
          },
        );
      }
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {},
      );
    }
  }

  static VoidCallback? _onStop;

  static Future<void> tryToSpeak(
    String text, {
    required String langCode,
    // Target ID for where to show warning popup
    String? targetID,
    BuildContext? context,
    ChatController? chatController,
    VoidCallback? onStart,
    VoidCallback? onStop,
  }) async {
    final prevOnStop = _onStop;
    _onStop = onStop;

    _tts.setErrorHandler((message) {
      _onError(message);
      prevOnStop?.call();
    });

    onStart?.call();

    await _tryToSpeak(
      text,
      langCode: langCode,
      targetID: targetID,
      context: context,
      chatController: chatController,
      onStart: onStart,
      onStop: onStop,
    );
  }

  /// A safer version of speak, that handles the case of
  /// the language not being supported by the TTS engine
  static Future<void> _tryToSpeak(
    String text, {
    required String langCode,
    // Target ID for where to show warning popup
    String? targetID,
    BuildContext? context,
    ChatController? chatController,
    VoidCallback? onStart,
    VoidCallback? onStop,
  }) async {
    chatController?.stopMediaStream.add(null);
    MatrixState.pangeaController.matrixState.audioPlayer?.stop();

    await _setSpeakingLanguage(langCode);

    final enableTTS = MatrixState
        .pangeaController.userController.profile.toolSettings.enableTTS;

    if (enableTTS) {
      final token = PangeaTokenText(
        offset: 0,
        content: text,
        length: text.length,
      );

      onStart?.call();
      await (_isLangFullySupported(langCode)
          ? _speak(
              text,
              langCode,
              [token],
            )
          : _speakFromChoreo(
              text,
              langCode,
              [token],
            ));
    } else if (targetID != null && context != null) {
      await _showTTSDisabledPopup(context, targetID);
    }

    onStop?.call();
  }

  static Future<void> _speak(
    String text,
    String langCode,
    List<PangeaTokenText> tokens,
  ) async {
    try {
      await stop();
      text = text.toLowerCase();

      Logs().i('Speaking: $text, langCode: $langCode');
      final result = await Future(
        () => (_tts.speak(text)),
        //     .timeout(
        //   const Duration(seconds: 5),
        //   // onTimeout: () {
        //   //   ErrorHandler.logError(
        //   //     e: "Timeout on tts.speak",
        //   //     data: {"text": text},
        //   //   );
        //   // },
        // ),
      );
      Logs().i('Finished speaking: $text, result: $result');

      // return type is dynamic but apparent its supposed to be 1
      // https://pub.dev/packages/flutter_tts
      // if (result != 1 && !kIsWeb) {
      //   ErrorHandler.logError(
      //     m: 'Unexpected result from tts.speak',
      //     data: {
      //       'result': result,
      //       'text': text,
      //     },
      //     level: SentryLevel.warning,
      //   );
      // }
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'text': text,
        },
      );
      await _speakFromChoreo(text, langCode, tokens);
    } finally {
      stop();
    }
  }

  static Future<void> _speakFromChoreo(
    String text,
    String langCode,
    List<PangeaTokenText> tokens,
  ) async {
    TextToSpeechResponse? ttsRes;
    try {
      loadingChoreoStream.add(true);
      ttsRes = await MatrixState.pangeaController.textToSpeech.get(
        TextToSpeechRequest(
          text: text,
          langCode: langCode,
          tokens: tokens,
          userL1:
              MatrixState.pangeaController.languageController.activeL1Code() ??
                  LanguageKeys.unknownLanguage,
          userL2:
              MatrixState.pangeaController.languageController.activeL2Code() ??
                  LanguageKeys.unknownLanguage,
        ),
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'text': text,
        },
      );
    } finally {
      loadingChoreoStream.add(false);
    }

    if (ttsRes == null) return;

    try {
      Logs().i('Speaking from choreo: $text, langCode: $langCode');
      final audioContent = base64Decode(ttsRes.audioContent);
      audioPlayer?.dispose();
      audioPlayer = AudioPlayer();
      await audioPlayer!.setAudioSource(
        BytesAudioSource(
          audioContent,
          ttsRes.mimeType,
        ),
      );
      await audioPlayer!.play();
    } catch (e, s) {
      ErrorHandler.logError(
        e: 'Error playing audio',
        s: s,
        data: {
          'error': e.toString(),
          'text': text,
        },
      );
    } finally {
      audioPlayer?.dispose();
      audioPlayer = null;
    }
  }

  static bool _isLangFullySupported(String langCode) {
    if (_availableLangCodes.contains(langCode)) {
      return true;
    }

    final langCodeShort = langCode.split("-").first;
    if (langCodeShort.isEmpty) {
      return false;
    }

    return _availableLangCodes.any((lang) => lang.startsWith(langCodeShort));
  }

  static Future<void> _showTTSDisabledPopup(
    BuildContext context,
    String targetID,
  ) async =>
      instructionsShowPopup(
        context,
        InstructionsEnum.ttsDisabled,
        targetID,
        showToggle: false,
        forceShow: true,
      );
}
