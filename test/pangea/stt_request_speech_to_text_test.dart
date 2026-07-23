import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_controller.dart';
import 'get_test_client.dart';

/// P1b.2/P1b.4 caller-level coverage of the REAL toolbar seams on a live
/// `PangeaMessageEvent` (built on the in-memory FakeMatrixApi client), driving
/// the actual `requestSpeechToText` / `requestSttTranslation` methods rather
/// than the `repairSttTokens` seam in isolation.
///
/// The tokenizer is stubbed via `PangeaMessageEvent.enrichSttHook` so we can
/// assert deterministically WHETHER each path reaches it, without any HTTP:
///  - `requestSpeechToText(requireTokens: true)`  -> tokenizes (toolbar).
///  - `requestSpeechToText(requireTokens: false)` -> does NOT tokenize.
///  - `requestSttTranslation(...)`                -> does NOT tokenize (flipping
///    it to require tokens turns the sentinel assertion RED).
///
/// The audio event deliberately uses languages (speaker_l1 = `de`, embed
/// lang_code = `fr`) that DIFFER from the l1/l2 the caller passes (`en`/`es`),
/// so the snapshot assertions prove the tokenizer inputs are EVENT-sourced (D6)
/// and never taken from the caller's/current language.

const _eventSpeakerL1 = 'de'; // on the audio event, != the caller's l1 (`en`)
const _embedLangCode = 'fr'; // inside the embed, != the caller's l2 (`es`)

Map<String, dynamic> _tokenLessEmbed() {
  final raw = File(
    'test/pangea/stt_golden/choreo_response_skip_tokenize.json',
  ).readAsStringSync();
  final embed = jsonDecode(raw) as Map<String, dynamic>;
  // Force a distinctive event language so the snapshot cannot accidentally
  // match the caller's l1/l2 (en/es) and still look "event-sourced".
  (embed['results'][0]['transcripts'][0] as Map<String, dynamic>)['lang_code'] =
      _embedLangCode;
  return embed;
}

PangeaToken _token(String content) => PangeaToken.fromJson({
  'text': {'content': content, 'offset': 0, 'length': content.length},
  'lemma': {'text': content, 'save_vocab': true, 'form': content},
  'pos': 'NOUN',
  'morph': <String, dynamic>{},
});

SpeechToTextResponseModel _tokenRich(String content) =>
    SpeechToTextResponseModel.fromJson(
      _tokenLessEmbed(),
    ).withFirstTranscriptTokens([STTToken(token: _token(content))]);

void main() {
  late Client client;
  late Room room;
  late Timeline timeline;
  late PangeaMessageEvent audioMessage;

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!voice:fakeServer.notExisting', client: client);
    final event = Event(
      type: EventTypes.Message,
      eventId: r'$audio1:fakeServer.notExisting',
      senderId: client.userID!,
      originServerTs: DateTime.now(),
      content: {
        'msgtype': 'm.audio',
        'body': 'recording.wav',
        // Event-sourced tokenizer inputs (D6): speaker_l1 lives on the event,
        // lang_code lives inside the embed. Neither comes from user settings.
        'speaker_l1': _eventSpeakerL1,
        'user_stt': _tokenLessEmbed(),
      },
      room: room,
    );
    // An empty timeline is sufficient: the STT read path sources everything
    // from the event's own content, and `aggregatedEvents` tolerates an event
    // that is not present in the timeline (returns empty related-event sets).
    timeline = await room.getTimeline();
    audioMessage = PangeaMessageEvent(
      event: event,
      timeline: timeline,
      ownMessage: true,
    );
  });

  tearDown(() async {
    // Restore the real tokenizer so state never leaks between tests.
    PangeaMessageEvent.enrichSttHook = enrichSttWithTokens;
    timeline.cancelSubscriptions();
    await client.dispose();
  });

  test(
    'the embed alone is text-usable but token-less (the decoupled-send shape)',
    () {
      final local = audioMessage.getSpeechToTextLocal();
      expect(local, isNotNull);
      expect(local!.hasUsableTranscript, isTrue);
      expect(local.hasUsableTokens, isFalse);
    },
  );

  test('R7 (a): selection resolves a token from the LOADER'
      's loaded token-rich '
      'STT (the SAME source the display shows); with the loader unloaded, no '
      'token is selectable', () {
    final controller = SelectModeController(audioMessage);
    addTearDown(controller.dispose);

    // Loader unloaded -> loadedTranscription null -> nothing selectable.
    expect(controller.loadedTranscription, isNull);
    expect(
      SelectModeController.selectedAudioToken(
        controller.loadedTranscription,
        (_) => true,
      ),
      isNull,
    );

    // The DISPLAY loads a token-rich STT; SELECTION reads the SAME value.
    final loaded = _tokenRich('hola');
    controller.transcriptionState.value = AsyncLoaded(loaded);

    expect(controller.loadedTranscription, same(loaded));
    final token = SelectModeController.selectedAudioToken(
      controller.loadedTranscription,
      (t) => t.text.content == 'hola',
    );
    // Teeth: reading a parallel source (or null) instead of the loader here
    // makes the resolved token null -> RED.
    expect(token, isNotNull);
    expect(token!.text.content, 'hola');
  });

  test(
    'R7 (c): requestSpeechToText(requireTokens:true) does NOT re-tokenize when '
    'the local STT already has tokens (attach-success common case)',
    () async {
      var enrichCalls = 0;
      PangeaMessageEvent.enrichSttHook = (base, snapshot) async {
        enrichCalls++;
        return base;
      };

      // An event whose embed is ALREADY token-rich (as if the attached
      // token-rich representation is present / the send carried tokens).
      final richEvent = Event(
        type: EventTypes.Message,
        eventId: r'$audio-rich:fakeServer.notExisting',
        senderId: client.userID!,
        originServerTs: DateTime.now(),
        content: {
          'msgtype': 'm.audio',
          'body': 'recording.wav',
          'speaker_l1': _eventSpeakerL1,
          'user_stt': _tokenRich('hola').toJson(),
        },
        room: room,
      );
      final richMessage = PangeaMessageEvent(
        event: richEvent,
        timeline: timeline,
        ownMessage: true,
      );

      final result = await richMessage.requestSpeechToText(
        'en',
        'es',
        requireTokens: true,
      );

      // Teeth: if requestSpeechToText re-tokenized a token-rich local, this
      // would be 1 -> RED.
      expect(enrichCalls, 0);
      expect(result.hasUsableTokens, isTrue);
    },
  );

  test('R8 HIGH: the transcription LOADER fetch requires tokens -- '
      'SelectModeController.requestTokenizedTranscription reaches the tokenizer '
      'on a token-less embed (so tap-to-select gets spans)', () async {
    final sentinel = Exception('tokenizer-reached');
    PangeaMessageEvent.enrichSttHook = (base, snapshot) async => throw sentinel;

    // requireTokens:true -> the token-less embed is repaired -> the tokenizer
    // is reached (throws the sentinel before the backend-less attach). Teeth:
    // reverting requireTokens:true returns the token-less embed WITHOUT
    // tokenizing -> no throw -> RED (dead taps).
    await expectLater(
      SelectModeController.requestTokenizedTranscription(
        audioMessage,
        'en',
        'es',
      ),
      throwsA(same(sentinel)),
    );
  });

  test(
    'R8 HIGH: a PERSISTED token-rich pangea.representation prevents re-tokenize '
    '(attach-success common case), with a token-LESS embed',
    () async {
      var enrichCalls = 0;
      PangeaMessageEvent.enrichSttHook = (base, snapshot) async {
        enrichCalls++;
        return base;
      };

      // A persisted token-rich representation whose transcript matches the
      // token-less embed ("hola mundo"/fr), aggregated to the audio event.
      final richStt = _tokenRich('hola mundo');
      final repEvent = Event(
        type: PangeaEventTypes.representation,
        eventId: r'$rep1:fakeServer.notExisting',
        senderId: client.userID!,
        originServerTs: DateTime.now(),
        content: {
          PangeaEventTypes.representation: PangeaRepresentation(
            langCode: _embedLangCode,
            text: 'hola mundo',
            originalSent: false,
            originalWritten: false,
            speechToText: richStt,
          ).toJson(),
        },
        room: room,
      );
      timeline.aggregatedEvents[audioMessage.eventId] = {
        PangeaEventTypes.representation: {repEvent},
      };

      final result = await audioMessage.requestSpeechToText(
        'en',
        'es',
        requireTokens: true,
      );

      // getSpeechToTextLocal(preferTokens) finds the PERSISTED token-rich rep,
      // so repairSttTokens sees a token-rich local and does NOT tokenize.
      // Teeth: reverting the persisted-rep preference -> re-tokenizes -> RED.
      expect(enrichCalls, 0);
      expect(result.hasUsableTokens, isTrue);
    },
  );

  test(
    'requestSpeechToText(requireTokens: true) tokenizes the token-less embed '
    'with a snapshot sourced from the EVENT language, not the caller args',
    () async {
      var enrichCalls = 0;
      SttLangSnapshot? seenSnapshot;
      final stopBeforeAttach = Exception('stop-before-attach');
      PangeaMessageEvent.enrichSttHook = (base, snapshot) async {
        enrichCalls++;
        seenSnapshot = snapshot;
        // Stop right after the tokenizer is reached, before the (backend-less)
        // Matrix attach write -- we only need to prove tokenization happened.
        throw stopBeforeAttach;
      };

      // Caller passes en/es (the "current" languages) -- DIFFERENT from the
      // event's de/fr. The snapshot must ignore these and use the event.
      await expectLater(
        audioMessage.requestSpeechToText('en', 'es', requireTokens: true),
        throwsA(same(stopBeforeAttach)),
      );

      expect(enrichCalls, 1);
      // D6: EVENT-sourced, proven by the distinctive de/fr (not the en/es args).
      expect(seenSnapshot!.senderL1, _eventSpeakerL1); // event's speaker_l1
      expect(seenSnapshot!.langCode, _embedLangCode); // embed's lang_code
      expect(
        seenSnapshot!.senderL2,
        _embedLangCode,
      ); // == the L2 (message lang)
    },
  );

  test('requestSpeechToText(requireTokens: false) returns the fast token-less '
      'embed and NEVER tokenizes', () async {
    var enrichCalls = 0;
    PangeaMessageEvent.enrichSttHook = (base, snapshot) async {
      enrichCalls++;
      return base;
    };

    // No attach/network on this path -- it returns the embed directly.
    final result = await audioMessage.requestSpeechToText('en', 'es');

    expect(enrichCalls, 0);
    expect(result.hasUsableTranscript, isTrue);
    expect(result.hasUsableTokens, isFalse);
  });

  test('requestSttTranslation reaches the decision and DECLINES tokenizing '
      '(text-only path is not dragged through the tokenizer)', () async {
    var enrichReached = false;
    PangeaMessageEvent.enrichSttHook = (base, snapshot) async {
      enrichReached = true; // flipped ONLY if the tokenizer is invoked
      return base;
    };

    // requestSttTranslation calls requestSpeechToText (no requireTokens), which
    // returns the token-less embed WITHOUT tokenizing, THEN progresses to the
    // translation fetch. That fetch fails deterministically here (createRequests
    // reads an uninitialized MatrixState -> LateInitializationError mentioning
    // `pangeaController`) -- a SPECIFIC, non-network, non-timeout signal that the
    // flow reached PAST the tokenizer decision. A hang or a pre-decision failure
    // would NOT carry this signature and would FAIL below, so a "never reached"
    // false-green is impossible.
    Object? error;
    try {
      await audioMessage
          .requestSttTranslation(langCode: 'en', l1Code: 'en', l2Code: 'es')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                throw TimeoutException('requestSttTranslation hung'),
          );
    } catch (e) {
      error = e;
    }

    // Declined tokenizing:
    expect(enrichReached, isFalse, reason: 'text-only path must not tokenize');
    // Positively reached-then-declined (not never-reached, not hung):
    expect(error, isNotNull);
    expect(error, isNot(isA<TimeoutException>()), reason: 'must not hang');
    expect(
      error.toString(),
      contains('pangeaController'),
      reason: 'reached the translation step past the tokenizer decision',
    );
  });
}
