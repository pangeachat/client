import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';
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

  test('requestSttTranslation NEVER tokenizes the token-less embed (text-only '
      'path is not dragged through the tokenizer)', () async {
    var enrichReached = false;
    PangeaMessageEvent.enrichSttHook = (base, snapshot) async {
      enrichReached = true; // the reached-decision sentinel
      return base;
    };

    // requestSttTranslation calls requestSpeechToText (no requireTokens),
    // which returns the token-less embed WITHOUT tokenizing, then a downstream
    // translation fetch that has no live backend here. We assert on the
    // SENTINEL (was the tokenizer reached?) -- settled before that fetch -- and
    // never depend on the downstream error. A timeout guards against any hang.
    try {
      await audioMessage
          .requestSttTranslation(langCode: 'en', l1Code: 'en', l2Code: 'es')
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Downstream translation fetch (no backend) is irrelevant to the
      // tokenizer decision asserted below.
    }

    // Teeth: if requestSttTranslation required tokens, this would be true.
    expect(enrichReached, isFalse);
  });
}
