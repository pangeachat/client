import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/lemma_use_example_messages.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'get_test_client.dart';

/// #8081 — the vocab details example-message walk: one example per source
/// message (dedup by event id, capped at 5), every used form recorded on its
/// example, and the fetch memoized across widget rebuilds. The walk is
/// exercised through the static
/// [LemmaUseExampleMessagesState.collectExampleMessages] seam — rendering the
/// bubbles themselves needs the full app bootstrap (MatrixState /
/// PangeaController), which no test in this repo does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;
  late Timeline timeline;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!examples:fakeServer.notExisting', client: client);
    timeline = await room.getTimeline();
  });

  tearDown(() async {
    timeline.cancelSubscriptions();
    await client.dispose();
  });

  PangeaToken token(String content, int offset) => PangeaToken.fromJson({
    'text': {'content': content, 'offset': offset, 'length': content.length},
    'lemma': {'text': content, 'save_vocab': true, 'form': content},
    'pos': 'NOUN',
    'morph': <String, dynamic>{},
  });

  /// Tokenizes [message] on single spaces, so token offsets always match.
  List<PangeaToken> tokenize(String message) {
    final tokens = <PangeaToken>[];
    int offset = 0;
    for (final word in message.split(' ')) {
      tokens.add(token(word, offset));
      offset += word.length + 1;
    }
    return tokens;
  }

  PangeaMessageEvent messageEvent(String eventId, String message) =>
      PangeaMessageEvent(
        event: Event(
          type: EventTypes.Message,
          eventId: eventId,
          senderId: client.userID!,
          originServerTs: DateTime.now(),
          content: {'msgtype': 'm.text', 'body': message},
          room: room,
        ),
        timeline: timeline,
        ownMessage: true,
      );

  OneConstructUse use(String lemma, String form, String eventId, DateTime ts) =>
      OneConstructUse(
        useType: ConstructUseTypeEnum.click,
        lemma: lemma,
        form: form,
        constructType: ConstructTypeEnum.vocab,
        category: 'other',
        xp: 1,
        metadata: ConstructUseMetaData(
          roomId: room.id,
          eventId: eventId,
          timeStamp: ts,
        ),
      );

  ConstructUses constructFor(List<OneConstructUse> uses) => ConstructUses(
    uses: uses,
    constructType: ConstructTypeEnum.vocab,
    lemma: 'correr',
    category: 'other',
  );

  /// A resolver over canned per-event messages, counting calls per event id.
  ({
    Future<ExampleMessage?> Function(OneConstructUse use) resolve,
    Map<String, int> calls,
  })
  resolverFor(Map<String, String> messagesByEventId) {
    final calls = <String, int>{};
    Future<ExampleMessage?> resolve(OneConstructUse use) async {
      final eventId = use.metadata.eventId!;
      calls[eventId] = (calls[eventId] ?? 0) + 1;
      final message = messagesByEventId[eventId];
      if (message == null) return null;
      return ExampleMessage(
        messageEvent: messageEvent(eventId, message),
        tokens: tokenize(message),
      );
    }

    return (resolve: resolve, calls: calls);
  }

  group('collectExampleMessages', () {
    test('dedups uses by event id and records every used form', () async {
      final base = DateTime(2026, 1, 1);
      final resolver = resolverFor({'\$e1': 'corro y corres mucho'});
      // Three uses of the same event: two distinct forms plus a duplicate.
      final examples =
          await LemmaUseExampleMessagesState.collectExampleMessages([
            use('correr', 'corro', '\$e1', base),
            use(
              'correr',
              'corres',
              '\$e1',
              base.add(const Duration(minutes: 1)),
            ),
            use(
              'correr',
              'corro',
              '\$e1',
              base.add(const Duration(minutes: 2)),
            ),
          ], resolver.resolve);

      expect(examples, hasLength(1));
      // Second and third uses hit the existing example, not the resolver.
      expect(resolver.calls['\$e1'], 1);
      // The preselect token is the first used form by position, and the
      // already-recorded second form registers as a duplicate.
      expect(examples.single.firstUsedToken?.text.content, 'corro');
      expect(examples.single.addToken('corres'), isFalse);
    });

    test('caps the walk at 5 example messages, newest first', () async {
      final base = DateTime(2026, 1, 1);
      final resolver = resolverFor({
        for (int i = 0; i < 6; i++) '\$e$i': 'corro numero $i',
      });
      final examples =
          await LemmaUseExampleMessagesState.collectExampleMessages([
            for (int i = 0; i < 6; i++)
              use('correr', 'corro', '\$e$i', base.add(Duration(minutes: i))),
          ], resolver.resolve);

      expect(examples, hasLength(5));
      // Walks newest-first: the oldest use never resolves.
      expect(resolver.calls.containsKey('\$e0'), isFalse);
    });

    test('skips unresolvable uses without breaking the walk', () async {
      final base = DateTime(2026, 1, 1);
      final resolver = resolverFor({'\$known': 'corro mucho'});
      final examples =
          await LemmaUseExampleMessagesState.collectExampleMessages([
            use('correr', 'corro', '\$known', base),
            use(
              'correr',
              'corro',
              '\$unknown',
              base.add(const Duration(minutes: 1)),
            ),
          ], resolver.resolve);

      expect(examples, hasLength(1));
      expect(examples.single.eventId, '\$known');
    });
  });

  testWidgets('memoizes the walk across rebuilds of the same construct', (
    tester,
  ) async {
    // A resolver that never resolves keeps the example list empty, so the
    // widget renders without the full app bootstrap the bubbles need.
    final calls = <String>[];
    Future<ExampleMessage?> resolve(OneConstructUse use) async {
      calls.add(use.metadata.eventId!);
      return null;
    }

    final construct = constructFor([
      use('correr', 'corro', '\$e1', DateTime(2026, 1, 1)),
    ]);

    Widget build() => MaterialApp(
      home: Scaffold(
        body: LemmaUseExampleMessages(
          construct: construct,
          client: client,
          resolveExampleMessage: resolve,
        ),
      ),
    );

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));

    // A new widget instance with the same construct id must not refetch.
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });
}
