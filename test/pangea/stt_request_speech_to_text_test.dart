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
/// assert deterministically WHETHER each path reaches it:
///  - `requestSpeechToText(requireTokens: true)`  -> tokenizes (toolbar).
///  - `requestSpeechToText(requireTokens: false)` -> does NOT tokenize.
///  - `requestSttTranslation(...)`                -> does NOT tokenize (proves
///    the text-only path is never dragged through the tokenizer; flipping it to
///    require tokens turns this RED).
///
/// The token-repair attach + the translation call reach the network; since the
/// tokenizer decision is settled BEFORE either, those paths are raced against a
/// short timeout and we assert on the (already-settled) tokenizer counters.

Map<String, dynamic> _tokenLessEmbed() {
  final raw = File(
    'test/pangea/stt_golden/choreo_response_skip_tokenize.json',
  ).readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
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
        'speaker_l1': 'en',
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
    'with an EVENT-sourced snapshot (D6)',
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

      await expectLater(
        audioMessage.requestSpeechToText('en', 'es', requireTokens: true),
        throwsA(same(stopBeforeAttach)),
      );

      expect(enrichCalls, 1);
      // D6: the snapshot is sourced from the AUDIO EVENT, not current settings.
      expect(seenSnapshot!.senderL1, 'en'); // from the event's speaker_l1
      expect(seenSnapshot!.langCode, 'es'); // from the embed's lang_code
      expect(seenSnapshot!.senderL2, 'es');
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
    var enrichCalls = 0;
    PangeaMessageEvent.enrichSttHook = (base, snapshot) async {
      enrichCalls++;
      return base;
    };

    // requestSttTranslation calls requestSpeechToText (no requireTokens), which
    // returns the token-less embed WITHOUT tokenizing, then the translation
    // repo -- which errors fast with no live backend. The tokenizer decision is
    // settled before that error.
    await expectLater(
      audioMessage.requestSttTranslation(
        langCode: 'en',
        l1Code: 'en',
        l2Code: 'es',
      ),
      throwsA(anything),
    );

    // Teeth: if requestSttTranslation asked for tokens, this would be 1 -> RED.
    expect(enrichCalls, 0);
  });
}
