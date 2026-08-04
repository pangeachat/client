import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/example_message_toolbar.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/lemma_use_example_messages.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'get_test_client.dart';

/// #8081 — the vocab details example-message chips: one chip per source
/// message (dedup by event id, capped at 5), matching forms bolded, resolver
/// memoized across rebuilds, and each chip a tappable target registered for
/// the message toolbar overlay to anchor over.
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

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
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
        message: message,
        tokens: tokenize(message),
      );
    }

    return (resolve: resolve, calls: calls);
  }

  /// All (text, isBold) segments across the rendered chips' RichTexts.
  List<(String, bool)> renderedSegments(WidgetTester tester) {
    final segments = <(String, bool)>[];
    for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
      (richText.text as TextSpan).visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          segments.add((span.text!, span.style?.fontWeight == FontWeight.bold));
        }
        return true;
      });
    }
    return segments;
  }

  testWidgets('dedups uses by event id and bolds every matched form', (
    tester,
  ) async {
    final base = DateTime(2026, 1, 1);
    final resolver = resolverFor({'\$e1': 'corro y corres mucho'});
    // Three uses of the same event: two distinct forms plus a duplicate.
    final construct = constructFor([
      use('correr', 'corro', '\$e1', base),
      use('correr', 'corres', '\$e1', base.add(const Duration(minutes: 1))),
      use('correr', 'corro', '\$e1', base.add(const Duration(minutes: 2))),
    ]);

    await tester.pumpWidget(
      wrap(
        LemmaUseExampleMessages(
          construct: construct,
          client: client,
          resolveExampleMessage: resolver.resolve,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InkWell), findsOneWidget);
    // Second and third uses hit the existing example, not the resolver.
    expect(resolver.calls['\$e1'], 1);

    final segments = renderedSegments(tester);
    expect(segments, contains(('corro', true)));
    expect(segments, contains(('corres', true)));
    expect(segments.where((s) => s.$1.contains('mucho') && !s.$2), isNotEmpty);
  });

  testWidgets('caps the list at 5 example messages', (tester) async {
    final base = DateTime(2026, 1, 1);
    final messages = {for (int i = 0; i < 6; i++) '\$e$i': 'corro numero $i'};
    final resolver = resolverFor(messages);
    final construct = constructFor([
      for (int i = 0; i < 6; i++)
        use('correr', 'corro', '\$e$i', base.add(Duration(minutes: i))),
    ]);

    await tester.pumpWidget(
      wrap(
        LemmaUseExampleMessages(
          construct: construct,
          client: client,
          resolveExampleMessage: resolver.resolve,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InkWell), findsNWidgets(5));
    // Walks newest-first: the oldest use never resolves.
    expect(resolver.calls.containsKey('\$e0'), isFalse);
  });

  testWidgets('memoizes the fetch across rebuilds of the same construct', (
    tester,
  ) async {
    final resolver = resolverFor({'\$e1': 'corro mucho'});
    final construct = constructFor([
      use('correr', 'corro', '\$e1', DateTime(2026, 1, 1)),
    ]);

    Widget build() => wrap(
      LemmaUseExampleMessages(
        construct: construct,
        client: client,
        resolveExampleMessage: resolver.resolve,
      ),
    );

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(resolver.calls['\$e1'], 1);

    // A new widget instance with the same construct id must not refetch.
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(resolver.calls['\$e1'], 1);
  });

  testWidgets('chips are tappable and registered as overlay anchor targets', (
    tester,
  ) async {
    final resolver = resolverFor({'\$e1': 'corro mucho'});
    final construct = constructFor([
      use('correr', 'corro', '\$e1', DateTime(2026, 1, 1)),
    ]);

    await tester.pumpWidget(
      wrap(
        LemmaUseExampleMessages(
          construct: construct,
          client: client,
          resolveExampleMessage: resolver.resolve,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, isNotNull);

    // The chip registers its render box under the analytics-specific target
    // id (never the raw event id — a chat panel showing the same message may
    // hold that GlobalKey), so the toolbar positioner can anchor over it.
    final targetId = analyticsExampleMessageTargetId('\$e1');
    expect(MatrixState.pAnyState.getRenderBox(targetId), isNotNull);
    expect(
      MatrixState.pAnyState.getRenderBox(targetId)!.size.height,
      greaterThan(0),
    );
  });
}
