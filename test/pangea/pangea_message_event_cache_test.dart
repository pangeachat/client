import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event_cache.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'get_test_client.dart';

/// #8393 stage 2 — [PangeaMessageEventCache] reuses one wrapper per event so
/// its parsed-representation memo survives timeline rebuilds. The dangerous
/// case is a representation arriving VIA SYNC after the wrapper is cached:
/// tokens and corrections land as child events after the message renders, and
/// a cache that missed them would freeze the message's tokens forever.

PangeaToken _token(String content, int offset) => PangeaToken.fromJson({
  'text': {'content': content, 'offset': offset, 'length': content.length},
  'lemma': {'text': content, 'save_vocab': true, 'form': content},
  'pos': 'NOUN',
  'morph': <String, dynamic>{},
});

PangeaMessageTokens _mergedTokens() => PangeaMessageTokens(
  tokens: [_token('buenosdías', 0)],
  detections: const [LanguageDetectionModel(langCode: 'es', confidence: 1)],
);

void main() {
  const messageEventId = r'$msg:fakeServer.notExisting';

  late Client client;
  late Room room;
  late Timeline timeline;
  late Event messageEvent;
  late PangeaMessageEventCache cache;

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!chat:fakeServer.notExisting', client: client);
    timeline = await room.getTimeline();
    messageEvent = Event(
      type: EventTypes.Message,
      eventId: messageEventId,
      senderId: '@othertest:fakeServer.notExisting',
      originServerTs: DateTime.now(),
      content: {
        'msgtype': 'm.text',
        'body': 'buenosdías',
        MessageConstants.tokensSent: _mergedTokens().toJson(),
      },
      room: room,
    );
    cache = PangeaMessageEventCache();
  });

  tearDown(() async {
    timeline.cancelSubscriptions();
    await client.dispose();
  });

  PangeaMessageEvent fromCache() =>
      cache.get(messageEvent, timeline, ownMessage: false);

  Event correctionEvent() => Event(
    type: PangeaEventTypes.representation,
    eventId: r'$corr:fakeServer.notExisting',
    senderId: client.userID!,
    originServerTs: DateTime.now(),
    content: {
      PangeaEventTypes.representation: PangeaMessageEvent.buildTokenCorrection(
        fullText: 'buenosdías',
        tokensSent: PangeaMessageTokens(
          tokens: [_token('buenos', 0), _token('días', 7)],
          detections: const [
            LanguageDetectionModel(langCode: 'es', confidence: 1),
          ],
        ),
        fallbackLangCode: 'es',
      ).toJson(),
    },
    room: room,
  );

  test('rebuild-style gets return the same instance', () {
    final first = fromCache();
    expect(identical(first, fromCache()), isTrue);
  });

  test('a representation arriving via sync refreshes the cached memo', () {
    final message = fromCache();
    // Parse and memoize the embedded (mis-tokenized) representation.
    expect(message.correctedSent!.tokens!.map((t) => t.text.content), [
      'buenosdías',
    ]);

    // The correction lands via sync: only the timeline aggregation changes.
    timeline.aggregatedEvents[messageEventId] = {
      PangeaEventTypes.representation: {correctionEvent()},
    };

    final refreshed = fromCache();
    expect(identical(message, refreshed), isTrue);
    expect(refreshed.correctedSent!.tokens!.map((t) => t.text.content), [
      'buenos',
      'días',
    ]);
  });

  test('a different timeline instance resets the cache', () async {
    final first = fromCache();
    final newTimeline = await room.getTimeline();
    final second = cache.get(messageEvent, newTimeline, ownMessage: false);
    expect(identical(first, second), isFalse);
    newTimeline.cancelSubscriptions();
  });
}
