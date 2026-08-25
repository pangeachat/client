import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_tts/flutter_tts.dart' as flutter_tts;
import 'package:just_audio/just_audio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';
import 'package:fluffychat/features/analytics/listening_exposure_declaration.dart';
import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/pangea/common/utils/strip_emojis.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_disambiguation.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_repo.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_repo.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_request_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_response_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_device_utterance.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_disabled_popup.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_routing.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/utils/multi_platform_audio_player.dart';
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

  Map<String, dynamic> toJson() => {
    'text': text,
    'langCode': langCode,
    'pos': pos,
    'morph': morph,
  };

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

/// A backend-TTS fetch starting or ending, scoped to the affordance that
/// asked for it. [targetId] is the `targetID` the caller passed to
/// [TtsController.tryToSpeak]; buttons filter on their own id so only the
/// tapped affordance shows a loading state, not every audio button on screen.
class TtsLoadingEvent {
  final String? targetId;
  final bool isLoading;

  const TtsLoadingEvent(this.targetId, this.isLoading);
}

class TtsController {
  static List<String> _availableLangCodes = [];

  /// Full voice list from flutter_tts `getVoices`. On native each entry carries
  /// a `quality` field; on web only `name` + `locale` (the engine drops quality
  /// and localService). Used to select a known-good device voice before falling
  /// back to backend TTS. See word-text-to-speech.instructions.md.
  static List<Map<String, String>> _voices = [];

  static final _tts = flutter_tts.FlutterTts();
  static final StreamController<TtsLoadingEvent> loadingChoreoStream =
      StreamController<TtsLoadingEvent>.broadcast();

  static AudioPlayer? audioPlayer;
  static _AudioRequest? _currentRequest;
  static int _requestCounter = 0;
  static int? _activeRequestId;

  /// The device utterance currently in flight, from the moment the plugin is
  /// asked to speak until it is known to have ended. The plugin's handlers
  /// are installed once and route to whatever is here, so each request hears
  /// only its own utterance's events — no per-request handler swap, and no
  /// previous request's callback fired by mistake.
  static TtsDeviceUtterance? _deviceUtterance;
  static bool _deviceHandlersInstalled = false;

  /// How long the device engine has to report a start before the utterance is
  /// treated as failed. Long enough for a network voice (Chrome's Google
  /// voices fetch audio before `start` fires) to load on an ordinary
  /// connection; short enough that a stuck plugin does not leave a tapped
  /// word marked playing indefinitely. Tunable; overridable in tests.
  @visibleForTesting
  static Duration deviceStartTimeout = const Duration(seconds: 3);

  /// How long `_stop` waits for the engine to confirm it stopped an in-flight
  /// utterance before issuing the next one. The web plugin ignores `speak`
  /// while it still believes the previous utterance is playing, and the
  /// browser confirms a cancel asynchronously — a next word issued inside that
  /// gap is silently dropped. Real confirmations arrive within milliseconds;
  /// the cap only bounds the wait when none ever comes.
  @visibleForTesting
  static Duration stopSettleTimeout = const Duration(milliseconds: 300);

  static bool _isCurrentRequestId(int requestId) =>
      _activeRequestId == requestId;

  static void _log(String message, String tid) {
    debugPrint('[TTS-DEBUG] [$tid] $message');
  }

  /// Wire the plugin's callbacks to the in-flight [_deviceUtterance]. Once per
  /// process; the plugin holds a single handler per event.
  static void _ensureDeviceHandlers() {
    if (_deviceHandlersInstalled) return;
    _deviceHandlersInstalled = true;
    _tts.setStartHandler(() => _deviceUtterance?.onEngineStart());
    _tts.setCompletionHandler(() => _deviceUtterance?.onEngineComplete());
    _tts.setCancelHandler(() => _deviceUtterance?.onEngineCancel());
    _tts.setErrorHandler((message) {
      _onError(message);
      _deviceUtterance?.onEngineError(message);
    });
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
    _voices = (voices ?? []).map<Map<String, String>>((v) {
      final voice = <String, String>{};
      (v as Map).forEach((key, value) {
        voice[key.toString()] = value?.toString() ?? '';
      });
      return voice;
    }).toList();
    _availableLangCodes = _voices
        .map((v) {
          // on iOS / web, the codes are in 'locale', but on Android, they are in 'name'
          final nameCode = v['name'] ?? '';
          final localeCode = v['locale'] ?? '';
          return localeCode.contains("-") ? localeCode : nameCode;
        })
        .toSet()
        .toList();
  }

  /// Whether the device currently offers a known-good voice for [langCode] —
  /// the same gate `tryToSpeak` applies before read-aloud playback, so a
  /// caller checking upfront (the settings toggle) can never disagree with
  /// what playback will do. See message-read-aloud.instructions.md.
  ///
  /// Always re-queries the engine: the user may have just downloaded an
  /// Enhanced/Premium voice after the dialog sent them to system settings, and
  /// the cached list predates it (#8282). The refreshed list is shared with
  /// playback, which then selects the new voice too.
  static Future<bool> hasKnownGoodVoiceFor(String langCode) async {
    await setAvailableLanguages();
    return TtsRouting.selectVoice(_voices, langCode, isWeb: kIsWeb).isKnownGood;
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
        'Stop called with different request than current: stopRequest=${request.toJson()} currentRequest=${_currentRequest?.toJson()}',
        'stop-${DateTime.now().millisecondsSinceEpoch}',
      );
      return;
    }
    await _stop();
  }

  static Future<void> _stop() async {
    try {
      // Mark the in-flight utterance BEFORE the engine is told to stop, so the
      // cancel it reports back is read as one we asked for — not as an engine
      // failure to rescue.
      final inFlight = _deviceUtterance;
      inFlight?.requestStop();

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

      // Let the engine confirm the stop before anyone issues the next
      // utterance. Resolves the stopped request's own await (its onStop and
      // measurement follow), and on the web resets the plugin's state so the
      // next `speak` is not silently ignored. Bounded: a confirmation that
      // never comes must not hold up the next word — and must not leave the
      // stopped request awaiting forever either, so it is settled on what is
      // known (heard if it started, cancelled if not).
      if (inFlight != null && !inFlight.engineHasEnded) {
        await inFlight.engineEnded.timeout(
          stopSettleTimeout,
          onTimeout: inFlight.onStopUnconfirmed,
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

    final ptResponse = PTV2Repo.instance.getCached(
      PTRequest(
        surface: request.text,
        langCode: request.langCode,
        userL1: userL1,
        // userL2 is excluded from the cache key, so any value resolves the same
        // entry.
        userL2: userL1,
      ),
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

    /// The surface this request comes from; determines which per-surface
    /// audio setting gates playback.
    required TtsUseCase useCase,
    // Target ID for where to show warning popup
    String? targetID,
    BuildContext? context,
    ChatController? chatController,
    VoidCallback? onStart,
    VoidCallback? onStop,
    double speed = 1.0,

    /// When provided, skip device TTS and use choreo with phoneme tags.
    /// If omitted, the PT v2 cache is checked automatically.
    String? ttsPhoneme,

    /// POS tag for disambiguation when resolving tts_phoneme from cache.
    String? pos,

    /// Morph features for disambiguation when resolving tts_phoneme from cache.
    Map<String, String>? morph,

    /// When false, this request never reaches backend TTS: it plays only if the
    /// device has a known-good voice for the language, and stays silent
    /// otherwise. Set by automatic message read-aloud, which fires on every
    /// eligible incoming message and so must not spend backend calls. See
    /// message-read-aloud.instructions.md.
    bool allowChoreoPlay = true,

    /// REQUIRED: the open measurement for this playback.
    ///
    /// Every call here plays target-language audio at a learner, so every call
    /// is listening — and the served figure is a TOTAL, so a path that measures
    /// nothing shortens the headline number rather than leaving a hole in a
    /// slice. Optional instrumentation would make forgetting it the default: a
    /// new read-aloud path would compile, analyze clean, pass every behavioural
    /// test, and silently shorten a teacher-visible total. Required is what
    /// turns that omission into a compile error, which is the only form of the
    /// rule that survives the next person who has never read this file.
    ///
    /// **Why a probe and not a bare category.** Naming a category is not enough
    /// to be measured: a measurement also has to be opened before playback and
    /// closed after it, in a `finally`, without awaiting anything. Taking a
    /// category and leaving the bracketing to the caller would leave exactly the
    /// hole this closes — a site that names a category and still counts nothing.
    /// So the caller hands over a probe it has already built, and the bracketing
    /// happens once, centrally, here.
    ///
    /// This entry point cannot build one. A single `tryToSpeak` serves automatic
    /// read-aloud, toolbar-open read-aloud, word taps and choice taps, and it
    /// takes neither a room nor an event id — only the CALLER knows the category
    /// and the room. Build a FRESH probe per call: it holds a running
    /// measurement.
    ///
    /// Design: docs/research/104-speaking-listening-minutes-v2.md, D-V2-1.
    required DosageTtsListeningProbe listening,

    /// REQUIRED: the lemmas this utterance covers, for listening exposure.
    ///
    /// Same shape and same reason as [listening]: this entry point is handed
    /// text, not tokens, so only the caller knows which constructs its
    /// utterance actually speaks. Required so a new read-aloud path cannot
    /// silently record nothing; use
    /// [ListeningExposureDeclaration.exempt] to say a path speaks no L2 lemma.
    ///
    /// See message-read-aloud.instructions.md (Word-level exposure).
    required ListeningExposureDeclaration exposure,
  }) async {
    final requestId = ++_requestCounter;
    // The measurement for THIS call. Bracketed here rather than at each call
    // site: the returned future cannot tell speech from silence (several exits
    // resolve having played nothing — the tool setting is off, the request was
    // superseded, or `allowChoreoPlay: false` met a device with no known-good
    // voice, which returns near instantly and still fires `onStop`), so timing
    // the call banks a near-zero interval for audio nobody heard. The
    // start/abort pair below brackets a route that was actually asked to play,
    // and only that.
    // Deliberately NOT latched: start and abort are paired PER ROUTE, so a
    // backend failure that falls back to the device is start/abort/start/end —
    // one banked interval, the failed one discarded — and a device failure
    // rescued by the backend is the same shape the other way round. A latch
    // would suppress the second route's start and leave the meter running from
    // the failed attempt.
    void guarded(VoidCallback callback, String name) {
      try {
        callback();
      } catch (e, s) {
        error_handler.ErrorHandler.logError(
          e: e,
          s: s,
          data: {'m': '$name threw (swallowed)'},
        );
      }
    }

    // Whether a route played the utterance THROUGH TO ITS END.
    //
    // Deliberately not "a route started". The listening meter banks whatever
    // played, because a learner who heard half a message did hear that half —
    // but word-level exposure is all-or-nothing per lemma, and a read stopped
    // after two words did not expose the learner to the rest of the sentence.
    // Both device and backend routes can start and then be cut off while still
    // reporting success (`TtsDeviceOutcome.played` covers "cut off by a stop",
    // and a Choreo `Loading interrupted` is treated as an expected
    // cancellation), so neither the start signal nor the return value can
    // stand in for completion.
    var completed = false;

    void reportPlaybackStarted() =>
        guarded(listening.started, 'onPlaybackStarted');
    void reportPlaybackAborted() =>
        guarded(listening.aborted, 'onPlaybackAborted');
    void reportPlaybackCompleted() => completed = true;

    final strippedText = stripEmojis(text);
    final request = _AudioRequest(
      text: strippedText,
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

    // On web, network voices (e.g. "Google Deutsch") load asynchronously and may
    // be absent from the initial list, so refresh each call. See
    // word-text-to-speech.instructions.md.
    if (_availableLangCodes.isEmpty || kIsWeb) {
      await setAvailableLanguages();
    }

    onStart?.call();

    try {
      await _tryToSpeak(
        strippedText,
        ttsPhoneme: ttsPhoneme,
        requestId: requestId,
        langCode: langCode,
        useCase: useCase,
        targetID: targetID,
        context: context,
        chatController: chatController,
        onStart: onStart,
        onStop: onStop,
        tid: transactionId,
        speed: speed,
        allowChoreoPlay: allowChoreoPlay,
        onPlaybackStarted: reportPlaybackStarted,
        onPlaybackCompleted: reportPlaybackCompleted,
        onPlaybackAborted: reportPlaybackAborted,
      );
    } catch (e, s) {
      // An affordance marked playing by onStart renders that state until
      // onStop clears it, and _tryToSpeak only calls onStop on the exits it
      // reaches — so a throw in between left the indicator stuck (#8375).
      // Backend and device playback failures are already handled inside; this
      // catches the setup around them.
      _log('tryToSpeak: failed before playback completed: $e', transactionId);
      onStop?.call();
      error_handler.ErrorHandler.logError(
        e: e,
        s: s,
        data: {'langCode': langCode, 'useCase': useCase.name},
      );
    } finally {
      // Only the active request may clear shared request state. Stranding it
      // makes `stop` decline to stop every later word.
      if (_isCurrentRequestId(requestId)) {
        _currentRequest = null;
        _activeRequestId = null;
      }
      // Close the measurement HERE: in a `finally`, so a throw out of TTS still
      // closes it, and AFTER the await, so nothing about it can delay speech.
      // It is synchronous and allocation-only — it appends to an in-memory
      // buffer and returns — and it emits nothing when playback never started.
      // Guarded like the other two, so telemetry can never surface to the
      // learner.
      guarded(listening.finish, 'listening.finish');
      // Exposure rides the same bracket, and only on a completed playback:
      // read-aloud stops on drafting, selection and focus loss, so minting for
      // an utterance that was cut off would bank words nobody heard.
      if (completed) {
        assert(
          exposure.exemptReason != null ||
              ListeningExposureBuffer.languageKey(exposure.langCode) ==
                  ListeningExposureBuffer.languageKey(langCode),
          'exposure declared ${exposure.langCode} but $langCode was spoken: '
          'a use filed under the wrong language cannot be separated later',
        );
        guarded(() => exposure.record(listening.userId()), 'exposure.record');
      }
    }
  }

  /// A safer version of speak, that handles the case of
  /// the language not being supported by the TTS engine
  static Future<void> _tryToSpeak(
    String text, {
    required int requestId,
    required String langCode,
    required TtsUseCase useCase,
    // Target ID for where to show warning popup
    String? targetID,
    BuildContext? context,
    ChatController? chatController,
    VoidCallback? onStart,
    VoidCallback? onStop,
    String? ttsPhoneme,
    required String tid,
    double speed = 1.0,
    bool allowChoreoPlay = true,
    VoidCallback? onPlaybackStarted,

    /// A route played this utterance THROUGH TO ITS END. Distinct from
    /// [onPlaybackStarted] plus a success return: both routes can start
    /// and then be cut off while still reporting success.
    VoidCallback? onPlaybackCompleted,
    VoidCallback? onPlaybackAborted,
  }) async {
    chatController?.stopMediaStream.add(null);
    MatrixState.pangeaController.matrixState.audioPlayer?.stop();

    await _setSpeakingLanguage(langCode, tid);

    // A null tool setting means the use case is ungated — see
    // TtsUseCase.voiceReply for the one case and why.
    final gate = useCase.toolSetting;
    final audioEnabled =
        gate == null ||
        MatrixState.pangeaController.userController.isToolEnabled(gate);

    if (audioEnabled) {
      final token = PangeaTokenText(
        offset: 0,
        content: text,
        length: text.length,
      );

      final selection = TtsRouting.selectVoice(
        _voices,
        langCode,
        isWeb: kIsWeb,
      );

      // Callers that disallow backend playback stay silent when the device has
      // no known-good voice, rather than falling back to a poor one. See
      // message-read-aloud.instructions.md.
      if (!allowChoreoPlay && !selection.isKnownGood) {
        _log(
          'tryToSpeak: silent, no known-good device voice and backend disallowed',
          tid,
        );
        onStop?.call();
        return;
      }

      final isSubscribed = MatrixState
          .pangeaController
          .subscriptionController
          .showSubscriptionGatedContent;

      // Routing gate (see word-text-to-speech.instructions.md): a phoneme
      // override needs backend; else device when it has a known-good voice;
      // else backend. Backend is Pro-only, so unsubscribed users stay on device.
      final useBackend =
          allowChoreoPlay &&
          TtsRouting.useBackend(
            hasPhoneme: ttsPhoneme != null,
            selection: selection,
            isSubscribed: isSubscribed,
          );
      _log(
        'tryToSpeak: route=${useBackend ? "backend" : "device"} '
        'knownGood=${selection.isKnownGood} hasVoice=${selection.hasVoice} '
        'voice=${selection.voice?['name']} subscribed=$isSubscribed '
        'phoneme=$ttsPhoneme',
        tid,
      );

      onStart?.call();

      if (!_isCurrentRequestId(requestId)) {
        _log('tryToSpeak: request superseded before playback start', tid);
        return;
      }

      if (useBackend) {
        final success = await _speakFromChoreo(
          text,
          langCode,
          [token],
          requestId: requestId,
          ttsPhoneme: ttsPhoneme,
          targetID: targetID,
          // Phoneme playback gets the full deadline and no device rescue:
          // the device cannot render the phoneme, so a fast fallback plays a
          // different reading than the transcription on screen (#8076).
          timeout: TtsRouting.backendTimeout(
            hasPhoneme: ttsPhoneme != null,
            hasVoice: selection.hasVoice,
          ),
          tid: tid,
          speed: speed,
          onPlaybackStarted: onPlaybackStarted,
          onPlaybackCompleted: onPlaybackCompleted,
        );
        // The backend was asked to play and did not. Whatever interval it opened
        // is not listening — drop it BEFORE the fallback opens its own, or the
        // time spent failing and switching routes is banked as audio heard.
        if (!success) onPlaybackAborted?.call();

        final allowFallback = TtsRouting.allowDeviceFallback(
          hasPhoneme: ttsPhoneme != null,
          hasVoice: selection.hasVoice,
        );
        if (!success && allowFallback && _isCurrentRequestId(requestId)) {
          _log('tryToSpeak: speaking from device on backend failure', tid);
          final rescued = await _speakFromDevice(
            text,
            langCode,
            [token],
            tid,
            requestId: requestId,
            speed: speed,
            voice: selection.voice,
            onPlaybackStarted: onPlaybackStarted,
            onPlaybackCompleted: onPlaybackCompleted,
          );
          if (rescued != TtsDeviceOutcome.played) onPlaybackAborted?.call();
        } else if (!success) {
          _log(
            'tryToSpeak: no device fallback '
            '(allowed=$allowFallback current=${_isCurrentRequestId(requestId)})',
            tid,
          );
        }
      } else {
        final outcome = await _speakFromDevice(
          text,
          langCode,
          [token],
          tid,
          requestId: requestId,
          speed: speed,
          voice: selection.voice,
          onPlaybackStarted: onPlaybackStarted,
          onPlaybackCompleted: onPlaybackCompleted,
        );
        // Anything but audio heard: drop whatever interval the device opened
        // BEFORE a rescue opens its own.
        if (outcome != TtsDeviceOutcome.played) onPlaybackAborted?.call();

        // The mirror of the backend→device fallback above. Only a FAILURE is
        // rescued — the engine never produced audio and nobody asked it to
        // stop. A cancel (the learner tapped stop, a later tap superseded
        // this one) asked for silence and gets it.
        final allowRescue = TtsRouting.allowBackendRescue(
          allowChoreoPlay: allowChoreoPlay,
          isSubscribed: isSubscribed,
        );
        if (outcome == TtsDeviceOutcome.failed &&
            allowRescue &&
            _isCurrentRequestId(requestId)) {
          _log('tryToSpeak: speaking from backend on device failure', tid);
          final rescued = await _speakFromChoreo(
            text,
            langCode,
            [token],
            requestId: requestId,
            targetID: targetID,
            // The device already had its turn; there is nothing left to race
            // the backend against, so it gets the full deadline.
            timeout: TtsRouting.backendTimeout(
              hasPhoneme: false,
              hasVoice: false,
            ),
            tid: tid,
            speed: speed,
            onPlaybackStarted: onPlaybackStarted,
            onPlaybackCompleted: onPlaybackCompleted,
          );
          if (!rescued) onPlaybackAborted?.call();
        } else if (outcome == TtsDeviceOutcome.failed) {
          _log(
            'tryToSpeak: no backend rescue '
            '(allowed=$allowRescue current=${_isCurrentRequestId(requestId)})',
            tid,
          );
        }
      }
    } else if (targetID != null && context != null) {
      TtsDisabledPopup.show(context, targetID, gate);
    }

    onStop?.call();
  }

  /// Speak [text] on the device engine and report how it ended.
  ///
  /// Always resolves. The plugin's `speak` future alone is not enough to wait
  /// on: it never resolves on the web when the utterance errors (which is how
  /// Chrome reports an interruption), nor on iOS when a later `stop` drops it.
  /// So the utterance is settled by whichever comes first — the engine's
  /// completion/cancel/error handler, the speak future, or the start
  /// watchdog — and the outcome says whether audio was heard
  /// ([TtsDeviceOutcome.played]), silence was asked for
  /// ([TtsDeviceOutcome.cancelled]) or the engine failed to play at all
  /// ([TtsDeviceOutcome.failed], eligible for backend rescue).
  static Future<TtsDeviceOutcome> _speakFromDevice(
    String text,
    String langCode,
    List<PangeaTokenText> tokens,
    String tid, {
    required int requestId,
    double speed = 1.0,

    /// The device voice to use, as `{name, locale}`. When omitted, the engine's
    /// default voice for the language (set via `_setSpeakingLanguage`) is used.
    Map<String, String>? voice,
    VoidCallback? onPlaybackStarted,

    /// A route played this utterance THROUGH TO ITS END. Distinct from
    /// [onPlaybackStarted] plus a success return: both routes can start
    /// and then be cut off while still reporting success.
    VoidCallback? onPlaybackCompleted,
  }) async {
    if (!_isCurrentRequestId(requestId)) {
      _log('Skipping device playback for superseded request', tid);
      return TtsDeviceOutcome.cancelled;
    }

    _ensureDeviceHandlers();
    final utterance = TtsDeviceUtterance(startTimeout: deviceStartTimeout);
    try {
      _log(
        'Speaking from device: $text, langCode: $langCode, voice: ${voice?['name']}',
        tid,
      );
      if (voice != null && (voice['name']?.isNotEmpty ?? false)) {
        await _tts.setVoice(voice);
      }
      text = text.toLowerCase();

      double setSpeed = speed;
      if (!kIsWeb) {
        try {
          final speedRange = await _tts.getSpeechRateValidRange;
          setSpeed = speed * speedRange.normal;
        } catch (e, s) {
          error_handler.ErrorHandler.logError(e: e, s: s, data: {'text': text});
        }
      }
      _tts.setSpeechRate(setSpeed);

      // A stop may have arrived during the awaits above; do not hand the
      // engine an utterance nobody wants any more.
      if (!_isCurrentRequestId(requestId)) {
        _log('Request superseded during device setup', tid);
        return TtsDeviceOutcome.cancelled;
      }

      // Device audio starts here. Installed as the in-flight utterance right
      // before `speak`, so the handlers route this engine's events here and
      // as few stale events from the previous utterance as possible.
      _deviceUtterance = utterance;
      utterance.arm();
      onPlaybackStarted?.call();
      // Not awaited directly: on the web this future never resolves when the
      // utterance errors, and on iOS it never resolves when a later stop
      // drops it. It is one of three signals that settle the utterance.
      unawaited(
        Future(() => _tts.speak(text)).then(
          (_) => utterance.onSpeakReturned(),
          onError: (Object e, StackTrace s) {
            _log('Error playing audio from device: $e', tid);
            error_handler.ErrorHandler.logError(
              e: e,
              s: s,
              data: {'text': text},
            );
            utterance.onSpeakThrew();
          },
        ),
      );
      final outcome = await utterance.outcome;
      // `played` covers an utterance that was cut off, because for listening
      // minutes the part that played still counts. Exposure needs the stricter
      // fact, which the utterance captures at settle time.
      if (utterance.playedToEnd) onPlaybackCompleted?.call();
      _log(
        'Device playback ended: ${outcome.name} '
        '(started=${utterance.started} stopRequested=${utterance.stopRequested} '
        'engineEnded=${utterance.engineHasEnded})',
        tid,
      );

      // A failure the engine has not itself closed (the start watchdog fired,
      // or `speak` returned before any event): tell the engine to drop the
      // utterance so it cannot start after we have moved on — the rescue
      // would otherwise play over it — and let it confirm, so the stale event
      // lands here rather than on the next utterance.
      if (outcome == TtsDeviceOutcome.failed && !utterance.engineHasEnded) {
        utterance.requestStop();
        await _tts.stop();
        await utterance.engineEnded.timeout(
          stopSettleTimeout,
          onTimeout: () {},
        );
      }
      return outcome;
    } catch (e, s) {
      _log('Error playing audio from device: $e', tid);
      debugger(when: kDebugMode);
      error_handler.ErrorHandler.logError(e: e, s: s, data: {'text': text});
      return TtsDeviceOutcome.failed;
    } finally {
      utterance.dispose();
      if (identical(_deviceUtterance, utterance)) _deviceUtterance = null;
    }
  }

  static Future<bool> _speakFromChoreo(
    String text,
    String langCode,
    List<PangeaTokenText> tokens, {
    required int requestId,
    String? ttsPhoneme,
    String? targetID,
    Duration timeout = const Duration(seconds: 10),
    required String tid,
    double speed = 1.0,
    VoidCallback? onPlaybackStarted,

    /// A route played this utterance THROUGH TO ITS END. Distinct from
    /// [onPlaybackStarted] plus a success return: both routes can start
    /// and then be cut off while still reporting success.
    VoidCallback? onPlaybackCompleted,
  }) async {
    _log('_speakFromChoreo: text="$text" ttsPhoneme=$ttsPhoneme', tid);
    TextToSpeechResponseModel? ttsRes;
    AudioPlayer? requestPlayer;

    loadingChoreoStream.add(TtsLoadingEvent(targetID, true));
    try {
      final result = await TextToSpeechRepo.instance
          .get(_request(text, langCode, tokens, ttsPhoneme))
          .timeout(timeout);
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
      loadingChoreoStream.add(TtsLoadingEvent(targetID, false));
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
      audioPlayer!.setSpeed(speed);
      final player = MultiPlatformAudioPlayer(
        audioPlayer: audioPlayer!,
        bytes: audioContent,
        name: 'tts_output_${DateTime.now().millisecondsSinceEpoch}.mp3',
        mimeType: 'audio/mpeg',
      );
      await player.setAudioSource();
      if (!_isCurrentRequestId(requestId)) {
        _log(
          'Choreo source loaded but request was superseded before play',
          tid,
        );
        return false;
      }
      // Backend audio starts here; `play()` resolves at playback end.
      onPlaybackStarted?.call();
      await player.play();
      _log('Audio playback from choreo completed', tid);
      // Reached only when `play()` resolved normally. The `Loading interrupted`
      // branch below returns success too — it is an expected cancellation, not
      // a failure — so a success return cannot stand in for completion.
      onPlaybackCompleted?.call();
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
}
