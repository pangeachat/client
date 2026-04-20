import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_tts/flutter_tts.dart' as flutter_tts;
import 'package:just_audio/just_audio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_disambiguation.dart';
import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_repo.dart';
import 'package:fluffychat/pangea/text_to_speech/text_to_speech_repo.dart';
import 'package:fluffychat/pangea/text_to_speech/text_to_speech_request_model.dart';
import 'package:fluffychat/pangea/text_to_speech/text_to_speech_response_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart'
    as error_handler;

class _AudioRequest {
  final String text;
  final String langCode;
  final String? pos;
  final Map<String, String>? morph;

  _AudioRequest({
    required this.text,
    required this.langCode,
    this.pos,
    this.morph,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _AudioRequest &&
        other.text == text &&
        other.langCode == langCode &&
        other.pos == pos &&
        const DeepCollectionEquality().equals(other.morph, morph);
  }

  @override
  int get hashCode =>
      text.hashCode ^
      langCode.hashCode ^
      (pos?.hashCode ?? 0) ^
      const DeepCollectionEquality().hash(morph);
}

class TtsController {
  static List<String> _availableLangCodes = [];

  static final _tts = flutter_tts.FlutterTts();
  static final StreamController<bool> loadingChoreoStream =
      StreamController<bool>.broadcast();

  static AudioPlayer? audioPlayer;
  static VoidCallback? _onStop;
  static _AudioRequest? _currentRequest;
  static int _requestCounter = 0;
  static int? _activeRequestId;

  static bool _isCurrentRequestId(int requestId) =>
      _activeRequestId == requestId;

  static void _log(String message, String tid) {
    debugPrint('[TTS-DEBUG] [$tid] $message');
  }

  static TextToSpeechRequestModel _request(
    String text,
    String langCode,
    List<PangeaTokenText> tokens,
    String? ttsPhoneme,
  ) => TextToSpeechRequestModel(
    text: text,
    langCode: langCode,
    tokens: tokens,
    userL1:
        MatrixState.pangeaController.userController.userL1Code ??
        LanguageKeys.unknownLanguage,
    userL2:
        MatrixState.pangeaController.userController.userL2Code ??
        LanguageKeys.unknownLanguage,
    ttsPhoneme: ttsPhoneme,
    speakingRate: 1.0,
  );

  static Future<void> _onError(dynamic message) async {
    if (message != 'canceled' && message != 'interrupted') {
      error_handler.ErrorHandler.logError(
        e: 'TTS error',
        data: {'message': message},
      );
    }
  }

  static Future<void> setAvailableLanguages() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _setAvailableBaseLanguages();
    } catch (e, s) {
      debugger(when: kDebugMode);
      error_handler.ErrorHandler.logError(e: e, s: s, data: {});
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

  static Future<void> _setSpeakingLanguage(String langCode, String tid) async {
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
      _log('Language not supported: $jsonData', tid);
      Sentry.addBreadcrumb(Breadcrumb.fromJson(jsonData));
    }
  }

  static Future<void> forceStop() async => _stop();

  static Future<void> stop({
    required String text,
    required String langCode,
    String? pos,
    Map<String, String>? morph,
  }) async {
    final request = _AudioRequest(
      text: text,
      langCode: langCode,
      pos: pos,
      morph: morph,
    );
    if (_currentRequest != null && _currentRequest != request) {
      _log(
        'Stop called with different request than current: stopRequest=$request currentRequest=$_currentRequest',
        'stop-${DateTime.now().millisecondsSinceEpoch}',
      );
      return;
    }
    await _stop();
  }

  static Future<void> _stop() async {
    try {
      // return type is dynamic but apparent its supposed to be 1
      // https://pub.dev/packages/flutter_tts
      final result = await (_tts.stop());
      audioPlayer?.stop();

      if (result != 1) {
        error_handler.ErrorHandler.logError(
          m: 'Unexpected result from tts.stop',
          data: {'result': result},
        );
      }
    } catch (e, s) {
      debugger(when: kDebugMode);
      error_handler.ErrorHandler.logError(e: e, s: s, data: {});
    }
  }

  /// Look up the PT v2 cache for [text] and return tts_phoneme if the word is a
  /// heteronym that can be disambiguated. Returns null for single-pronunciation
  /// words or when no PT data is cached.
  static String? _resolveTtsPhonemeFromCache(
    _AudioRequest request, {
    required String tid,
  }) {
    final userL1 = MatrixState.pangeaController.userController.userL1Code;
    if (userL1 == null) return null;

    final ptResponse = PTV2Repo.getCachedResponse(
      request.text,
      request.langCode,
      userL1,
    );
    _log(
      '_resolveTtsPhonemeFromCache: text="${request.text}" lang=${request.langCode} cached=${ptResponse != null} count=${ptResponse?.pronunciations.length ?? 0} pos=${request.pos} morph=${request.morph}',
      tid,
    );
    if (ptResponse == null || ptResponse.pronunciations.length <= 1) {
      return null;
    }

    final result = disambiguate(
      ptResponse.pronunciations,
      pos: request.pos,
      morph: request.morph,
    );
    return result.ttsPhoneme;
  }

  static Future<void> tryToSpeak(
    String text, {
    required String langCode,
    // Target ID for where to show warning popup
    String? targetID,
    BuildContext? context,
    ChatController? chatController,
    VoidCallback? onStart,
    VoidCallback? onStop,

    /// When provided, skip device TTS and use choreo with phoneme tags.
    /// If omitted, the PT v2 cache is checked automatically.
    String? ttsPhoneme,

    /// POS tag for disambiguation when resolving tts_phoneme from cache.
    String? pos,

    /// Morph features for disambiguation when resolving tts_phoneme from cache.
    Map<String, String>? morph,
  }) async {
    final requestId = ++_requestCounter;
    final request = _AudioRequest(
      text: text,
      langCode: langCode,
      pos: pos,
      morph: morph,
    );
    _activeRequestId = requestId;
    _currentRequest = request;
    final transactionId = DateTime.now().millisecondsSinceEpoch.toString();
    // Auto-resolve tts_phoneme from PT cache if not explicitly provided.
    final explicitPhoneme = ttsPhoneme;
    ttsPhoneme ??= _resolveTtsPhonemeFromCache(request, tid: transactionId);
    _log(
      'tryToSpeak: text="${request.text}" explicitPhoneme=$explicitPhoneme resolvedPhoneme=$ttsPhoneme pos=${request.pos} morph=${request.morph}',
      transactionId,
    );

    await _stop();

    final prevOnStop = _onStop;
    _onStop = onStop;

    if (_availableLangCodes.isEmpty) {
      await setAvailableLanguages();
    }

    _tts.setErrorHandler((message) {
      _onError(message);
      prevOnStop?.call();
    });

    onStart?.call();

    await _tryToSpeak(
      text,
      ttsPhoneme: ttsPhoneme,
      requestId: requestId,
      langCode: langCode,
      targetID: targetID,
      context: context,
      chatController: chatController,
      onStart: onStart,
      onStop: onStop,
      tid: transactionId,
    );

    // Only the active request may clear shared request state.
    if (_isCurrentRequestId(requestId)) {
      _currentRequest = null;
      _activeRequestId = null;
    }
  }

  /// A safer version of speak, that handles the case of
  /// the language not being supported by the TTS engine
  static Future<void> _tryToSpeak(
    String text, {
    required int requestId,
    required String langCode,
    // Target ID for where to show warning popup
    String? targetID,
    BuildContext? context,
    ChatController? chatController,
    VoidCallback? onStart,
    VoidCallback? onStop,
    String? ttsPhoneme,
    required String tid,
  }) async {
    chatController?.stopMediaStream.add(null);
    MatrixState.pangeaController.matrixState.audioPlayer?.stop();

    await _setSpeakingLanguage(langCode, tid);

    final enableTTS = MatrixState
        .pangeaController
        .userController
        .profile
        .toolSettings
        .enableTTS;

    if (enableTTS) {
      final token = PangeaTokenText(
        offset: 0,
        content: text,
        length: text.length,
      );

      final langSupported = _isLangFullySupported(langCode);

      onStart?.call();

      if (!_isCurrentRequestId(requestId)) {
        _log('tryToSpeak: request superseded before playback start', tid);
        return;
      }

      // When tts_phoneme is provided, skip device TTS and use choreo with phoneme tags.
      if (ttsPhoneme != null || !langSupported) {
        final success = await _speakFromChoreo(
          text,
          langCode,
          [token],
          requestId: requestId,
          ttsPhoneme: ttsPhoneme,
          timeout: langSupported
              ? const Duration(seconds: 1)
              : const Duration(seconds: 10),
          tid: tid,
        );

        // fallback to device TTS if language is supported but choreo fails (e.g. due to timeout)
        if (!success && langSupported && _isCurrentRequestId(requestId)) {
          _log('tryToSpeak: speaking from device on choreo failure', tid);
          await _speakFromDevice(
            text,
            langCode,
            [token],
            tid,
            requestId: requestId,
          );
        } else if (!success && !_isCurrentRequestId(requestId)) {
          _log('tryToSpeak: skipped fallback for superseded request', tid);
        }
      } else {
        _log(
          'tryToSpeak: speaking from device, language fully supported, no phoneme provided',
          tid,
        );
        await _speakFromDevice(
          text,
          langCode,
          [token],
          tid,
          requestId: requestId,
        );
      }
    } else if (targetID != null && context != null) {
      OverlayUtil.showTTSDisabledPopup(context, targetID);
    }

    onStop?.call();
  }

  static Future<bool> _speakFromDevice(
    String text,
    String langCode,
    List<PangeaTokenText> tokens,
    String tid, {
    required int requestId,
  }) async {
    if (!_isCurrentRequestId(requestId)) {
      _log('Skipping device playback for superseded request', tid);
      return false;
    }

    try {
      _log('Speaking from device: $text, langCode: $langCode', tid);
      text = text.toLowerCase();
      await Future(() => (_tts.speak(text)));
      _log('Audio playback from device completed', tid);
      return true;
    } catch (e, s) {
      _log('Error playing audio from device: $e', tid);
      debugger(when: kDebugMode);
      error_handler.ErrorHandler.logError(e: e, s: s, data: {'text': text});
      return false;
    }
  }

  static Future<bool> _speakFromChoreo(
    String text,
    String langCode,
    List<PangeaTokenText> tokens, {
    required int requestId,
    String? ttsPhoneme,
    Duration timeout = const Duration(seconds: 10),
    required String tid,
  }) async {
    _log('_speakFromChoreo: text="$text" ttsPhoneme=$ttsPhoneme', tid);
    TextToSpeechResponseModel? ttsRes;
    AudioPlayer? requestPlayer;

    loadingChoreoStream.add(true);
    try {
      final result = await TextToSpeechRepo.get(
        MatrixState.pangeaController.userController.accessToken,
        _request(text, langCode, tokens, ttsPhoneme),
      ).timeout(timeout);
      if (result.isError) {
        _log('Choreo TTS API call failed: ${result.error}', tid);
        return false;
      }
      _log('Choreo TTS API call succeeded', tid);
      ttsRes = result.result!;
    } on TimeoutException catch (_) {
      _log('Choreo TTS API call timed out', tid);
      return false;
    } catch (e, s) {
      _log('Error during Choreo TTS API call: $e', tid);
      error_handler.ErrorHandler.logError(
        e: 'Error in TTS API call',
        s: s,
        data: {'text': text, 'error': e.toString()},
      );
      return false;
    } finally {
      loadingChoreoStream.add(false);
    }

    try {
      _log('Speaking from choreo: $text, langCode: $langCode', tid);
      if (!_isCurrentRequestId(requestId)) {
        _log('Skipping choreo playback for superseded request', tid);
        return false;
      }
      final audioContent = base64Decode(ttsRes.audioContent);
      if (audioPlayer != null) {
        await audioPlayer!.dispose();
      }
      requestPlayer = AudioPlayer();
      audioPlayer = requestPlayer;
      final blob = html.Blob([audioContent], 'audio/mpeg');
      final url = html.Url.createObjectUrlFromBlob(blob);
      await requestPlayer.setAudioSource(AudioSource.uri(Uri.parse(url)));
      if (!_isCurrentRequestId(requestId)) {
        _log(
          'Choreo source loaded but request was superseded before play',
          tid,
        );
        return false;
      }
      await requestPlayer.play();
      _log('Audio playback from choreo completed', tid);
      return true;
    } catch (e, s) {
      if (e.toString().contains('Loading interrupted')) {
        _log(
          'Choreo loading interrupted; treating as expected cancellation',
          tid,
        );
        return true;
      }
      _log('Error playing audio from choreo: $e', tid);
      error_handler.ErrorHandler.logError(
        e: 'Error playing audio',
        s: s,
        data: {'error': e.toString(), 'text': text},
      );
      return false;
    } finally {
      if (requestPlayer != null) {
        await requestPlayer.dispose();
      }
      if (identical(audioPlayer, requestPlayer)) {
        audioPlayer = null;
      }
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
}
