import 'dart:convert';
import 'dart:developer';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/models/llm_feedback_model.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';
import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_representation_event.dart';
import 'package:fluffychat/routes/chat/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';
import 'package:fluffychat/routes/chat/events/models/stt_translation_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_repo.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_request.dart';
import 'package:fluffychat/routes/chat/events/repo/language_detection_response.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/audio_encoding_enum.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_repo.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_repo.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_request_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_response_model.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_repo.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_request_model.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_response_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_audio_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import '../../../../features/languages/language_constants.dart';
import '../../../../pangea/common/utils/error_handler.dart';
import '../../../../widgets/matrix.dart';
import '../constants/pangea_event_types.dart';

class PangeaMessageEvent {
  late Event _event;
  final Timeline timeline;
  final bool ownMessage;

  PangeaMessageEvent({
    required Event event,
    required this.timeline,
    required this.ownMessage,
  }) {
    if (event.type != EventTypes.Message) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        m: "${event.type} should not be used to make a PangeaMessageEvent",
        data: {"event": event.toJson()},
      );
    }
    _event = event;
  }

  //the timeline filters the edits and uses the original events
  //so this event will always be the original and the sdk getter body
  //handles getting the latest text from the aggregated events
  Event get event => _event;

  String get body => _latestEdit.body;

  String get senderId => _event.senderId;

  DateTime get originServerTs => _latestEdit.originServerTs;

  String get eventId => _latestEdit.eventId;

  Room get room => _event.room;

  bool get isAudioMessage => _event.messageType == MessageTypes.Audio;

  bool get isTextMessage => _event.messageType == MessageTypes.Text;

  String? get _l2Code => MatrixState.pangeaController.userController.userL2Code;

  String? get _l1Code =>
      MatrixState.pangeaController.userController.userL1?.langCode;

  Event get _latestEdit => _event.getDisplayEvent(timeline);

  // get audio events that are related to this event
  Set<Event> get ttsEvents => _latestEdit
      .aggregatedEvents(timeline, PangeaEventTypes.textToSpeech)
      .where((element) {
        return element.content.tryGet<Map<String, dynamic>>(
              MessageConstants.transcription,
            ) !=
            null;
      })
      .toSet();

  Set<Event> get _sttTranslationEvents =>
      _latestEdit.aggregatedEvents(timeline, PangeaEventTypes.sttTranslation);

  List<RepresentationEvent> get _repEvents => _latestEdit
      .aggregatedEvents(timeline, PangeaEventTypes.representation)
      .map((e) {
        try {
          return RepresentationEvent(
            event: e,
            parentMessageEvent: _latestEdit,
            timeline: timeline,
          );
        } catch (_) {
          // A malformed relation (e.g. a wrong-type event aggregated under the
          // representation relation) throws in RepresentationEvent's
          // constructor. Skip it so a single bad relation can never abort the
          // whole representation-list build and hide valid persisted tokens.
          return null;
        }
      })
      .whereType<RepresentationEvent>()
      .sorted((a, b) {
        if (a.event == null) return -1;
        if (b.event == null) return 1;
        return b.event!.originServerTs.compareTo(a.event!.originServerTs);
      })
      .toList();

  ChoreoRecordModel? get _embeddedChoreo {
    try {
      if (_latestEdit.content[MessageConstants.choreoRecord] == null) {
        return null;
      }
      return ChoreoRecordModel.fromJson(
        _latestEdit.content[MessageConstants.choreoRecord]
            as Map<String, dynamic>,
        originalWrittenContent,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: _latestEdit.content,
        m: "error parsing choreoRecord",
      );
      return null;
    }
  }

  PangeaMessageTokens? _tokensSafe(Map<String, dynamic>? content) {
    try {
      if (content == null) return null;
      return PangeaMessageTokens.fromJson(content);
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: e,
        s: s,
        data: content ?? {},
        m: "error parsing tokensSent",
      );
      return null;
    }
  }

  List<RepresentationEvent>? _representations;
  List<RepresentationEvent> get representations {
    if (_representations != null) return _representations!;
    _representations = [];
    try {
      final tokens = _tokensSafe(
        _latestEdit.content[MessageConstants.tokensSent]
            as Map<String, dynamic>?,
      );

      // If originalSent has no tokens, there is not way to generate a tokens event
      // and send it as a related event, since original sent has not eventID to set
      // as parentEventId. In this case, it's better to generate a new representation
      // with an eventID and send the related tokens event to that representation.
      // This is a rare situation, and has only been seen with some bot messages.
      if (tokens != null) {
        final lang = tokens.detections?.isNotEmpty == true
            ? tokens.detections!.first.langCode
            : null;

        final original = PangeaRepresentation(
          langCode: lang ?? LanguageKeys.unknownLanguage,
          text: _latestEdit.body,
          originalSent: true,
          originalWritten: false,
        );

        _representations!.add(
          RepresentationEvent(
            parentMessageEvent: _latestEdit,
            content: original,
            tokens: tokens,
            choreo: _embeddedChoreo,
            timeline: timeline,
          ),
        );
      }
    } catch (err, s) {
      ErrorHandler.logError(
        m: "error parsing originalSent",
        e: err,
        s: s,
        data: {"event": _latestEdit.toJson()},
      );
    }

    if (_latestEdit.content[MessageConstants.originalWritten] != null) {
      try {
        _representations!.add(
          RepresentationEvent(
            parentMessageEvent: _latestEdit,
            content: PangeaRepresentation.fromJson(
              _latestEdit.content[MessageConstants.originalWritten]
                  as Map<String, dynamic>,
            ),
            tokens: _tokensSafe(
              _latestEdit.content[MessageConstants.tokensWritten]
                  as Map<String, dynamic>?,
            ),
            timeline: timeline,
          ),
        );
      } catch (err, s) {
        ErrorHandler.logError(
          m: "error parsing originalWritten",
          e: err,
          s: s,
          data: {"event": _latestEdit.toJson()},
        );
      }
    }

    _representations!.addAll(_repEvents);
    return _representations!;
  }

  RepresentationEvent? get originalSent => representations.firstWhereOrNull(
    (element) => element.content.originalSent,
  );

  /// Vocab + morph construct uses the sender actually produced in this
  /// message — the single source for analytics and used-vocab tracking.
  /// Typed messages read the sent representation's tokens; voice messages
  /// read the embedded STT transcript. Both yield the same [OneConstructUse]
  /// shape (spoken words score as `pvm`), so callers don't special-case audio
  /// (issue #7659).
  List<OneConstructUse>? get constructUses => isAudioMessage
      // A TOKEN consumer: analytics needs the tokens, so prefer a token-rich
      // representation over the provisional empty-token embed a decoupled send
      // leaves behind (D5).
      ? getSpeechToTextLocal(preferTokens: true)?.constructs(room.id, eventId)
      : originalSent?.vocabAndMorphUses;

  RepresentationEvent? get originalWritten => representations.firstWhereOrNull(
    (element) => element.content.originalWritten,
  );

  String get originalWrittenContent {
    String? written = originalSent?.content.text;
    if (originalWritten != null && !originalWritten!.content.originalSent) {
      written = originalWritten!.text;
    } else if (originalSent?.choreo != null) {
      written = originalSent!.choreo!.originalText;
    }

    return written ?? body;
  }

  String get messageDisplayLangCode {
    if (isAudioMessage) {
      final stt = getSpeechToTextLocal();
      if (stt == null) return LanguageKeys.unknownLanguage;
      return stt.langCode;
    }

    final bool immersionMode = MatrixState.pangeaController.userController
        .isToolEnabled(ToolSetting.immersionMode);

    final String? originalLangCode = originalSent?.langCode;

    final String? langCode = immersionMode ? _l2Code : originalLangCode;
    return langCode ?? LanguageKeys.unknownLanguage;
  }

  RepresentationEvent? get messageDisplayRepresentation =>
      _representationByLanguage(messageDisplayLangCode);

  /// Gets the message display text for the current language code.
  /// If the message display text is not available for the current language code,
  /// it returns the message body.
  String get messageDisplayText =>
      messageDisplayRepresentation?.text ?? _latestEdit.body;

  TextDirection get textDirection =>
      LanguageConstants.rtlLanguageCodes.contains(messageDisplayLangCode)
      ? TextDirection.rtl
      : TextDirection.ltr;

  void updateLatestEdit() {
    _representations = null;
  }

  RepresentationEvent? _representationByLanguage(
    String langCode, {
    bool Function(RepresentationEvent)? filter,
  }) => representations.firstWhereOrNull(
    (element) =>
        element.langCode.split("-")[0] == langCode.split("-")[0] &&
        (filter?.call(element) ?? true),
  );

  /// The newest representation carrying a `speechToText` payload. When
  /// [preferTokens] is set, a token-rich representation (usable transcript AND
  /// non-empty tokens) is preferred over an earlier text-only one, so token
  /// consumers surface the attached tokens instead of the provisional empty
  /// embed; without it the first STT representation (reps are newest-first)
  /// wins, matching the R0 behaviour.
  RepresentationEvent? _speechToTextRepresentation({
    bool preferTokens = false,
    SpeechToTextResponseModel? matchEmbed,
  }) {
    // The persisted STT representations, NEWEST-first, paired with their
    // payload (`representations` is already sorted newest-first). Reading a
    // malformed rep can THROW; a bad rep is treated as absent and skipped so it
    // can never hide the valid persisted tokens or force a network repair.
    final sttReps = <(RepresentationEvent, SpeechToTextResponseModel)>[];
    for (final rep in representations) {
      try {
        final stt = rep.content.speechToText;
        if (stt != null) sttReps.add((rep, stt));
      } catch (_) {
        // Malformed representation -> treat as absent; continue the scan.
      }
    }
    if (sttReps.isEmpty) return null;

    if (preferTokens) {
      // Trust a token-rich rep ONLY when it matches the CURRENT authoritative
      // transcript, so an OLDER token-rich rep never beats a NEWER text-only rep
      // (stale utterance). Computed FRESH from live reps -- no cache.
      final chosen = pickTokenRichRepStt(
        sttReps.map((p) => p.$2).toList(),
        matchEmbed,
      );
      if (chosen != null) {
        return sttReps.firstWhereOrNull((p) => identical(p.$2, chosen))?.$1;
      }
    }
    // Fall back to the newest STT representation (text-only if that is newest).
    return sttReps.first.$1;
  }

  /// From the persisted STT representation payloads [repStts] (NEWEST-first),
  /// picks the token-rich one that matches the CURRENT authoritative transcript:
  /// [embed] if it has a usable transcript, ELSE the newest rep's transcript.
  /// So an OLDER token-rich rep can never beat a NEWER text-only rep (a stale
  /// utterance): (a) newest rep token-rich -> matches itself -> returned;
  /// (b) newest text-only + older token-rich SAME utterance -> matches ->
  /// returned (tokens); (c) newest text-only + older token-rich DIFFERENT
  /// utterance -> no match -> null (caller falls back to the newest text-only
  /// rep). With no authoritative transcript anywhere, any token-rich rep is
  /// acceptable (nothing to diverge from). Computed FRESH each read from live
  /// reps -- no cache, no static/parallel state. Pure -> unit-testable.
  @visibleForTesting
  static SpeechToTextResponseModel? pickTokenRichRepStt(
    List<SpeechToTextResponseModel> repStts,
    SpeechToTextResponseModel? embed,
  ) {
    final authoritative = (embed != null && embed.hasUsableTranscript)
        ? embed
        : repStts.firstWhereOrNull((s) => s.hasUsableTranscript);
    return repStts.firstWhereOrNull((stt) {
      if (!stt.hasUsableTranscript || !stt.hasUsableTokens) return false;
      return authoritative == null || sttTranscriptsMatch(authoritative, stt);
    });
  }

  /// Whether two STT responses describe the SAME utterance: identical usable
  /// transcript text and the same short language code. Used to gate whether a
  /// token-rich representation may replace the provisional embed's tokens, so a
  /// stale/foreign representation can never contaminate display or analytics.
  @visibleForTesting
  static bool sttTranscriptsMatch(
    SpeechToTextResponseModel a,
    SpeechToTextResponseModel b,
  ) {
    if (!a.hasUsableTranscript || !b.hasUsableTranscript) return false;
    return a.transcript.text == b.transcript.text &&
        a.langCode.split('-').first == b.langCode.split('-').first;
  }

  Event? _getTextToSpeechLocal(String langCode, String text, String? voice) {
    for (final audio in ttsEvents) {
      final dataMap = audio.content.tryGetMap(MessageConstants.transcription);
      if (dataMap == null || !dataMap.containsKey(ModelKey.tokens)) continue;

      try {
        final PangeaAudioEventData audioData = PangeaAudioEventData.fromJson(
          dataMap as dynamic,
        );

        if (audioData.langCode == langCode &&
            audioData.text == text &&
            audioData.voice == voice) {
          return audio;
        }
      } catch (e, s) {
        debugger(when: kDebugMode);
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {"event": audio.toJson()},
          m: "error parsing data in getTextToSpeechLocal",
        );
      }
    }
    return null;
  }

  /// Selects the usable STT for an audio message. Prefers a non-empty
  /// embedded transcript; an empty (exhausted-fallback) or unparseable embed
  /// must fall through to a representation the bot may have re-transcribed
  /// later, rather than short-circuiting to null. Mirrors the bot's
  /// `_is_valid_stt_response` fall-through gate (get_audio_stt.py).
  /// [representation] is a thunk, evaluated ONLY when the embed is not usable,
  /// so a valid embed returns without touching a (possibly malformed)
  /// representation. Usability is the full [hasUsableTranscript] gate, not just
  /// non-empty results: a nested-empty response is parseable but would crash
  /// `.transcript`/`.langCode`, so it must fall through, not be selected.
  /// [preferTokens] (default false) is byte-identical to R0: the first
  /// text-usable source wins (embed before representation) and the
  /// representation thunk is never evaluated when the embed is usable. When set,
  /// a token-rich source (usable transcript AND non-empty tokens) is preferred
  /// -- so a token consumer surfaces the attached tokens rather than the
  /// provisional empty-token embed a decoupled send leaves -- falling back to
  /// any text-usable source (embed first) and never returning null while a
  /// text-usable embed exists (D5).
  @visibleForTesting
  static SpeechToTextResponseModel? selectUsableStt({
    required SpeechToTextResponseModel? embedded,
    required SpeechToTextResponseModel? Function() representation,
    bool preferTokens = false,
  }) {
    final embedUsable = embedded != null && embedded.hasUsableTranscript;
    // Fast path: a usable embed wins unless we need tokens it lacks. In the
    // default mode this returns before the representation thunk is touched.
    if (embedUsable && (!preferTokens || embedded.hasUsableTokens)) {
      return embedded;
    }
    final rep = representation();
    final repUsable = rep != null && rep.hasUsableTranscript;
    if (preferTokens) {
      // Only prefer a token-rich rep that MATCHES the provisional embed's
      // transcript (text + language); a stale/foreign rep must not replace the
      // embed's trusted content. With no usable embed, any token-rich rep wins.
      if (repUsable &&
          rep.hasUsableTokens &&
          (!embedUsable || sttTranscriptsMatch(embedded, rep))) {
        return rep;
      }
      if (embedUsable) return embedded;
      return repUsable ? rep : null;
    }
    return repUsable ? rep : null;
  }

  SpeechToTextResponseModel? getSpeechToTextLocal({bool preferTokens = false}) {
    // Check for STT embedded directly in the audio event content
    // (user-sent audio embeds under userStt, bot-sent audio under botTranscription)
    final rawEmbeddedStt =
        event.content.tryGetMap(MessageConstants.userStt) ??
        event.content.tryGetMap(MessageConstants.botTranscription);

    SpeechToTextResponseModel? embedded;
    if (rawEmbeddedStt != null) {
      try {
        embedded = SpeechToTextResponseModel.fromJson(
          Map<String, dynamic>.from(rawEmbeddedStt),
        );
      } catch (err, s) {
        // A parse error on the embed is not fatal: fall through to a
        // representation that may hold a valid transcript.
        ErrorHandler.logError(
          e: err,
          s: s,
          data: {"event": _event.toJson()},
          m: "error parsing embedded stt",
        );
      }
    }

    return selectUsableStt(
      embedded: embedded,
      preferTokens: preferTokens,
      // Lazy + guarded: only read when the embed is not usable (or lacks tokens
      // a token consumer needs), and a malformed related representation must not
      // throw (it is logged and treated as absent), so a usable embed is never
      // blocked by a broken representation. A token-rich representation is only
      // trusted when its transcript matches the embed (persisted-data guard).
      representation: () {
        try {
          return _speechToTextRepresentation(
            preferTokens: preferTokens,
            matchEmbed: embedded,
          )?.content.speechToText;
        } catch (err, s) {
          ErrorHandler.logError(
            e: err,
            s: s,
            data: {"event": _event.toJson()},
            m: "error reading stt representation",
          );
          return null;
        }
      },
    );
  }

  SttTranslationModel? _getSttTranslationLocal(String langCode) {
    final events = _sttTranslationEvents;
    final List<SttTranslationModel> translations = [];
    for (final event in events) {
      try {
        final translation = SttTranslationModel.fromJson(event.content);
        translations.add(translation);
      } catch (e) {
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: "Failed to parse STT translation",
            data: {
              "eventID": event.eventId,
              "content": event.content,
              "error": e.toString(),
            },
          ),
        );
      }
    }

    return translations.firstWhereOrNull((t) => t.langCode == langCode);
  }

  Future<PangeaAudioFile> requestTextToSpeech(
    String langCode,
    String? voice,
  ) async {
    final local = _getTextToSpeechLocal(langCode, messageDisplayText, voice);
    if (local != null) {
      final file = await local.getPangeaAudioFile();
      if (file != null) return file;
    }

    final rep = _representationByLanguage(langCode);
    final tokensResp = await rep?.requestTokens();
    final request = TextToSpeechRequestModel(
      text: rep?.content.text ?? body,
      tokens: tokensResp?.result?.map((t) => t.text).toList() ?? [],
      langCode: langCode,
      userL1: _l1Code ?? LanguageKeys.unknownLanguage,
      userL2: _l2Code ?? LanguageKeys.unknownLanguage,
      voice: voice,
    );

    final result = await TextToSpeechRepo.instance.get(request);

    if (result.error != null) {
      throw Exception("Error getting text to speech: ${result.error}");
    }

    final response = result.result!;
    final audioBytes = base64.decode(response.audioContent);
    final fileName =
        "audio_for_${_event.eventId}_$langCode.${response.fileExtension}";

    final file = PangeaAudioFile(
      bytes: audioBytes,
      name: fileName,
      mimeType: response.mimeType,
      duration: response.durationMillis,
      waveform: response.waveform,
      tokens: response.ttsTokens,
    );

    room.sendFileEvent(
      file,
      extraContent: {
        'info': {
          ...file.info,
          MessageConstants.duration: response.durationMillis,
        },
        'org.matrix.msc3245.voice': {},
        'org.matrix.msc1767.audio': {
          MessageConstants.duration: response.durationMillis,
          'waveform': response.waveform,
        },
        MessageConstants.transcription: response
            .toPangeaAudioEventData(rep?.text ?? body, langCode, voice)
            .toJson(),
        "m.relates_to": {
          "rel_type": PangeaEventTypes.textToSpeech,
          "event_id": _event.eventId,
        },
      },
    );

    return file;
  }

  /// Test seam: the single tokenize step used by the display-only token repair
  /// in [requestSpeechToText]. Overridable so a caller-level test can assert
  /// WHETHER the tokenizer is reached (e.g. that [requestSttTranslation] never
  /// tokenizes) without hitting the network. Defaults to the real helper.
  @visibleForTesting
  static Future<SpeechToTextResponseModel> Function(
    SpeechToTextResponseModel base,
    SttLangSnapshot snapshot,
  )
  enrichSttHook = enrichSttWithTokens;

  /// Snapshots the tokenizer inputs from THIS audio event (see [SttLangSnapshot]
  /// -- lang from the transcript, `sender_l1` from the event's `speaker_l1`), so
  /// a token repair uses the message's own language, not the reader's settings.
  SttLangSnapshot _sttLangSnapshot(SpeechToTextResponseModel baseStt) =>
      SttLangSnapshot.fromBaseStt(
        baseStt,
        speakerL1: _event.content.tryGet<String>('speaker_l1'),
      );

  /// Languages for a FROM-SCRATCH re-ASR (no embed to snapshot): prefer the
  /// event's own embedded sender languages so a later READER language change can
  /// never bypass the message's snapshot; fall back to the passed reader
  /// languages only when the event carries none. Pure + testable.
  @visibleForTesting
  static ({String userL1, String userL2}) reAsrLanguages({
    required String? eventSpeakerL1,
    required String? eventSpeakerL2,
    required String fallbackL1,
    required String fallbackL2,
  }) => (
    userL1: eventSpeakerL1 ?? fallbackL1,
    userL2: eventSpeakerL2 ?? fallbackL2,
  );

  /// [requireTokens] turns this into the shared TOKEN-REPAIR primitive (display
  /// only -- it never records analytics). Only when the caller requires tokens
  /// AND the local embed lacks them does it tokenize the embedded text, attach
  /// the `pangea.representation` best-effort, and return the token-rich result.
  /// The toolbar loader passes `requireTokens: true`; text-only callers
  /// (e.g. [requestSttTranslation]) leave the default `false` so a usable
  /// token-less embed is served fast, never dragged through the tokenizer.
  Future<SpeechToTextResponseModel> requestSpeechToText(
    String l1Code,
    String l2Code, {
    bool requireTokens = false,
  }) async {
    if (!isAudioMessage) {
      throw 'Calling getSpeechToText on non-audio message';
    }

    final speechToTextLocal = getSpeechToTextLocal(preferTokens: requireTokens);
    if (speechToTextLocal != null) {
      return repairSttTokens(
        local: speechToTextLocal,
        requireTokens: requireTokens,
        snapshot: _sttLangSnapshot(speechToTextLocal),
        enrich: enrichSttHook,
        attach: (rich) => attachSttRepresentation(
          send: room.sendPangeaEvent,
          parentEventId: eventId,
          richStt: rich,
        ),
      );
    }

    final matrixFile = await _event.downloadAndDecryptAttachment();
    // Event-sourced languages: prefer the message's own speaker_l1/l2 over the
    // reader's live settings, so a language change never bypasses the snapshot.
    final reAsrLangs = reAsrLanguages(
      eventSpeakerL1: _event.content.tryGet<String>('speaker_l1'),
      eventSpeakerL2: _event.content.tryGet<String>('speaker_l2'),
      fallbackL1: l1Code,
      fallbackL2: l2Code,
    );
    final result = await SpeechToTextRepo.instance.get(
      SpeechToTextRequestModel(
        audioContent: matrixFile.bytes,
        audioEvent: _event,
        config: SpeechToTextAudioConfigModel(
          encoding: mimeTypeToAudioEncoding(matrixFile.mimeType),
          sampleRateHertz: 22050,
          userL1: reAsrLangs.userL1,
          userL2: reAsrLangs.userL2,
        ),
      ),
    );

    if (result.error != null) {
      throw result.error!;
    }

    final stt = result.result!;
    if (stt.results.isEmpty) {
      // Exhausted-fallback: fromJson no longer throws for `results: []`
      // (R0-2), but this on-demand request has nothing usable to hand back.
      // Throw here so the existing AsyncLoader/AsyncError "transcription
      // failed" UX (select_mode_controller.dart, overlay_message.dart) keeps
      // working instead of receiving an empty model it doesn't guard for.
      throw Exception('SpeechToText: no transcript available for audio');
    }

    _sendSttRepresentationEvent(stt);
    return stt;
  }

  Future<String> requestSttTranslation({
    required String langCode,
    required String l1Code,
    required String l2Code,
  }) async {
    // First try to access the local translation event via a representation event
    final local = _getSttTranslationLocal(langCode);
    if (local != null) return local.translation;

    final stt = await requestSpeechToText(l1Code, l2Code);
    final res = await FullTextTranslationRepo.instance.get(
      FullTextTranslationRequestModel(
        text: stt.transcript.text,
        tgtLang: l1Code,
        userL2: l2Code,
        userL1: l1Code,
      ),
    );

    if (res.isError) {
      throw res.error!;
    }

    final translation = SttTranslationModel(
      translation: res.result!.bestTranslation,
      langCode: l1Code,
    );

    _sendSttTranslationEvent(sttTranslation: translation);
    return translation.translation;
  }

  Future<String?> requestRepresentationByDetectedLanguage() async {
    LanguageDetectionResponse? resp;
    final result = await LanguageDetectionRepo.instance.get(
      LanguageDetectionRequest(
        text: _latestEdit.body,
        senderl1: _l1Code,
        senderl2: _l2Code,
      ),
    );

    if (result.isError) return null;
    resp = result.result!;

    final langCode = resp.detections.firstOrNull?.langCode;
    if (langCode == null) return null;
    if (langCode == originalSent?.langCode) {
      return originalSent?.event?.eventId;
    }

    final res = await _requestRepresentation(
      originalSent?.content.text ?? _latestEdit.body,
      langCode,
      originalSent?.langCode ?? LanguageKeys.unknownLanguage,
      originalSent: originalSent == null,
    );

    if (res.isError) return null;
    return _sendRepresentationEvent(res.result!);
  }

  Future<FullTextTranslationResponseModel> requestTranslationByL1({
    List<LLMFeedbackModel<FullTextTranslationResponseModel>>? feedback,
  }) async {
    if (_l1Code == null || _l2Code == null) {
      throw Exception("Missing language codes");
    }

    if (feedback == null) {
      final includedIT =
          originalSent?.choreo?.endedWithIT(originalSent!.text) == true;
      RepresentationEvent? rep;
      if (!includedIT) {
        // if the message didn't go through translation, get any l1 rep
        rep = _representationByLanguage(_l1Code!);
      } else {
        // if the message went through translation, get the non-original
        // l1 rep since originalWritten could contain some l2 words
        // (https://github.com/pangeachat/client/issues/3591)
        rep = _representationByLanguage(
          _l1Code!,
          filter: (rep) => !rep.content.originalWritten,
        );
      }
      if (rep != null) {
        return FullTextTranslationResponseModel(
          translation: rep.text,
          translations: [rep.text],
          source: messageDisplayLangCode,
        );
      }
    }

    final includedIT =
        originalSent?.choreo?.endedWithIT(originalSent!.text) == true;

    final String srcLang = includedIT
        ? (originalWritten?.langCode ?? _l1Code!)
        : (originalSent?.langCode ?? _l2Code!);

    final text = includedIT ? originalWrittenContent : messageDisplayText;
    final resp = await FullTextTranslationRepo.instance.get(
      FullTextTranslationRequestModel(
        text: text,
        srcLang: srcLang,
        tgtLang: _l1Code!,
        userL2:
            MatrixState.pangeaController.userController.userL2Code ??
            LanguageKeys.unknownLanguage,
        userL1: _l1Code!,
        feedback: feedback,
      ),
    );

    if (resp.isError) throw resp.error!;
    _sendRepresentationEvent(
      PangeaRepresentation(
        langCode: _l1Code!,
        text: resp.result!.bestTranslation,
        originalSent: false,
        originalWritten: false,
      ),
    );
    return resp.result!;
  }

  Future<Result<PangeaRepresentation>> _requestRepresentation(
    String text,
    String targetLang,
    String sourceLang, {
    bool originalSent = false,
    List<LLMFeedbackModel<FullTextTranslationResponseModel>>? feedback,
  }) async {
    _representations = null;

    final res = await FullTextTranslationRepo.instance.get(
      FullTextTranslationRequestModel(
        text: text,
        srcLang: sourceLang,
        tgtLang: targetLang,
        userL2: _l2Code ?? LanguageKeys.unknownLanguage,
        userL1: _l1Code ?? LanguageKeys.unknownLanguage,
        feedback: feedback,
      ),
    );

    return res.isError
        ? Result.error(res.error!)
        : Result.value(
            PangeaRepresentation(
              langCode: targetLang,
              text: res.result!.bestTranslation,
              originalSent: originalSent,
              originalWritten: false,
            ),
          );
  }

  Future<String?> _sendRepresentationEvent(
    PangeaRepresentation representation,
  ) async {
    final repEvent = await room.sendPangeaEvent(
      content: representation.toJson(),
      parentEventId: _latestEdit.eventId,
      type: PangeaEventTypes.representation,
    );
    return repEvent?.eventId;
  }

  Future<Event?> _sendSttRepresentationEvent(
    SpeechToTextResponseModel stt,
  ) async {
    final representation = PangeaRepresentation(
      langCode: stt.langCode,
      text: stt.transcript.text,
      originalSent: false,
      originalWritten: false,
      speechToText: stt,
    );

    _representations = null;
    return room.sendPangeaEvent(
      content: representation.toJson(),
      parentEventId: _latestEdit.eventId,
      type: PangeaEventTypes.representation,
    );
  }

  Future<Event?> _sendSttTranslationEvent({
    required SttTranslationModel sttTranslation,
  }) => room.sendPangeaEvent(
    content: sttTranslation.toJson(),
    parentEventId: _latestEdit.eventId,
    type: PangeaEventTypes.sttTranslation,
  );
}
