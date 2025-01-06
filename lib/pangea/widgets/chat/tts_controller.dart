import 'dart:async';
import 'dart:developer';

import 'package:fluffychat/pangea/controllers/user_controller.dart';
import 'package:fluffychat/pangea/enum/instructions_enum.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/widgets/chat/missing_voice_button.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart' as flutter_tts;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:text_to_speech/text_to_speech.dart';

class TtsController {
  String? get targetLanguage =>
      MatrixState.pangeaController.languageController.userL2?.langCode;

  List<String> _availableLangCodes = [];
  final flutter_tts.FlutterTts _tts = flutter_tts.FlutterTts();
  final TextToSpeech _alternativeTTS = TextToSpeech();
  StreamSubscription? _languageSubscription;

  UserController get userController =>
      MatrixState.pangeaController.userController;

  TtsController() {
    setupTTS();
    _languageSubscription =
        userController.stateStream.listen((_) => setupTTS());
  }

  bool get _useAlternativeTTS {
    return PlatformInfos.isWindows;
  }

  Future<void> dispose() async {
    await _tts.stop();
    await _languageSubscription?.cancel();
  }

  void _onError(dynamic message) {
    // the package treats this as an error, but it's not
    // don't send to sentry
    if (message == 'canceled' || message == 'interrupted') {
      return;
    }

    ErrorHandler.logError(
      e: 'TTS error',
      data: {
        'message': message,
      },
    );
  }

  Future<void> setupTTS() async {
    try {
      if (_useAlternativeTTS) {
        await _setupAltTTS();
      } else {
        _tts.setErrorHandler(_onError);
        debugger(when: kDebugMode && targetLanguage == null);

        _tts.setLanguage(
          targetLanguage ?? "en",
        );

        await _tts.awaitSpeakCompletion(true);

        final voices = (await _tts.getVoices) as List?;
        _availableLangCodes = (voices ?? [])
            .map((v) {
              // on iOS / web, the codes are in 'locale', but on Android, they are in 'name'
              final nameCode = v['name']?.split("-").first;
              final localeCode = v['locale']?.split("-").first;
              return nameCode.length == 2 ? nameCode : localeCode;
            })
            .toSet()
            .cast<String>()
            .toList();
      }
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {},
      );
    } finally {
      debugPrint("availableLangCodes: $_availableLangCodes");
      final enableTTSSetting = userController.profile.toolSettings.enableTTS;
      if (enableTTSSetting != isLanguageFullySupported) {
        await userController.updateProfile(
          (profile) {
            profile.toolSettings.enableTTS = isLanguageFullySupported;
            return profile;
          },
          waitForDataInSync: true,
        );
      }
    }
  }

  Future<void> _setupAltTTS() async {
    try {
      final languages = await _alternativeTTS.getLanguages();
      _availableLangCodes =
          languages.map((lang) => lang.split("-").first).toSet().toList();

      debugPrint("availableLangCodes: $_availableLangCodes");

      final langsMatchingTarget = languages
          .where(
            (lang) =>
                targetLanguage != null &&
                lang.toLowerCase().startsWith(targetLanguage!.toLowerCase()),
          )
          .toList();

      if (langsMatchingTarget.isNotEmpty) {
        await _alternativeTTS.setLanguage(langsMatchingTarget.first);
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

  Future<void> stop() async {
    try {
      // return type is dynamic but apparent its supposed to be 1
      // https://pub.dev/packages/flutter_tts
      final result =
          await (_useAlternativeTTS ? _alternativeTTS.stop() : _tts.stop());

      if (!_useAlternativeTTS && result != 1) {
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

  Future<void> _showMissingVoicePopup(
    BuildContext context,
    String eventID,
  ) async {
    await MatrixState.pangeaController.instructions.showInstructionsPopup(
      context,
      InstructionsEnum.missingVoice,
      eventID,
      showToggle: false,
      customContent: const Padding(
        padding: EdgeInsets.only(top: 12),
        child: MissingVoiceButton(),
      ),
      forceShow: true,
    );
    return;
  }

  /// A safer version of speak, that handles the case of
  /// the language not being supported by the TTS engine
  Future<void> tryToSpeak(
    String text,
    BuildContext context,
    // TODO - make non-nullable again
    String? eventID,
  ) async {
    if (!MatrixState
        .pangeaController.userController.profile.toolSettings.enableTTS) {
      return;
    }

    if (isLanguageFullySupported) {
      await _speak(text);
    } else {
      ErrorHandler.logError(
        e: 'Language not supported by TTS engine',
        data: {
          'targetLanguage': targetLanguage,
        },
      );
      if (eventID != null) {
        await _showMissingVoicePopup(context, eventID);
      }
    }
  }

  Future<void> _speak(String text) async {
    try {
      stop();

      Logs().i('Speaking: $text');
      final result = await Future(
        () => (_useAlternativeTTS
                ? _alternativeTTS.speak(text)
                : _tts.speak(text))
            .timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            ErrorHandler.logError(
              e: "Timeout on tts.speak",
              data: {"text": text},
            );
          },
        ),
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
    }
  }

  bool get isLanguageFullySupported =>
      _availableLangCodes.contains(targetLanguage);
}

extension on (Future,) {
  timeout(Duration duration, {required Null Function() onTimeout}) {}
}
