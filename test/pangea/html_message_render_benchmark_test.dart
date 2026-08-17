import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';
import 'package:fluffychat/routes/chat/html_message.dart';
import 'package:fluffychat/routes/chat/toolbar/message_toolbar_host.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// Render coverage + benchmark for the token-heavy [HtmlMessage] path
/// (issue #8393).
///
/// The correctness tests pin the behavior the #8393 refactor must preserve:
/// every token of a token-dense message renders as its own interactive
/// [UnderlineText]. The benchmark repeatedly rebuilds the same message —
/// the exact cost paid per timeline rebuild on every sync — and prints an
/// average ms/rebuild (no timing assertions, so CI stays deterministic;
/// run it on two commits to compare them).

/// Twelve letter-only words: a digit in a lemma would be filtered out by
/// [HtmlMessage.tokens].
const _words = [
  'buenos',
  'días',
  'quiero',
  'practicar',
  'palabras',
  'nuevas',
  'porque',
  'aprender',
  'idiomas',
  'siempre',
  'resulta',
  'divertido',
];

class _BenchmarkMessage {
  final String body;
  final List<PangeaToken> tokens;

  _BenchmarkMessage._(this.body, this.tokens);

  /// [wordCount] words with real offsets, cycling through [_words].
  factory _BenchmarkMessage.ofLength(int wordCount) {
    final tokens = <PangeaToken>[];
    final buffer = StringBuffer();
    for (var i = 0; i < wordCount; i++) {
      final word = _words[i % _words.length];
      if (i > 0) buffer.write(' ');
      final offset = buffer.length;
      buffer.write(word);
      tokens.add(
        PangeaToken.fromJson({
          'text': {'content': word, 'offset': offset, 'length': word.length},
          'lemma': {'text': word, 'save_vocab': true, 'form': word},
          'pos': 'NOUN',
          'morph': <String, dynamic>{},
        }),
      );
    }
    return _BenchmarkMessage._(buffer.toString(), tokens);
  }
}

class _FakeToolbarHost implements MessageToolbarHost {
  _FakeToolbarHost(this.room);

  @override
  final Room room;

  @override
  Timeline? get timeline => null;

  @override
  ChatController? get chatController => null;

  @override
  void setSelectedEvent(Event event) {}

  @override
  void clearSelectedEvents() {}

  @override
  Future<void> showTokenFeedbackDialog(
    TokenInfoFeedbackRequestData requestData,
    String langCode,
    PangeaMessageEvent event,
  ) async {}
}

void main() {
  late Client client;
  late Room room;
  late Timeline timeline;

  setUp(() async {
    MatrixState.pangeaController = FakePangeaController();
    client = await getTestClient();
    // Quiesce the sync loop before the widget-test body runs: its retry
    // timers would trip the binding's pending-timer invariant.
    client.backgroundSync = false;
    client.abortSync();
    room = Room(id: '!bench:fakeServer.notExisting', client: client);
    timeline = await room.getTimeline();
  });

  tearDown(() async {
    timeline.cancelSubscriptions();
    await client.dispose();
  });

  Widget host(_BenchmarkMessage message, PangeaMessageEvent event) =>
      MaterialApp(
        home: Scaffold(
          body: HtmlMessage(
            html: message.body,
            room: room,
            fontSize: 16,
            linkStyle: const TextStyle(),
            onOpen: (_) {},
            event: event.event,
            pangeaMessageEvent: event,
            controller: _FakeToolbarHost(room),
          ),
        ),
      );

  PangeaMessageEvent messageEvent(_BenchmarkMessage message) =>
      PangeaMessageEvent(
        event: Event(
          type: EventTypes.Message,
          eventId: r'$bench:fakeServer.notExisting',
          senderId: '@bench:fakeServer.notExisting',
          originServerTs: DateTime.now(),
          content: {
            'msgtype': 'm.text',
            'body': message.body,
            MessageConstants.tokensSent: PangeaMessageTokens(
              tokens: message.tokens,
              detections: const [
                LanguageDetectionModel(langCode: 'es', confidence: 1),
              ],
            ).toJson(),
          },
          room: room,
        ),
        timeline: timeline,
        // Own message: the benchmark exercises the render pipeline, not the
        // subscription-gated new-token lookup of received messages.
        ownMessage: true,
      );

  testWidgets('every token of a 60-word message renders interactively', (
    tester,
  ) async {
    final message = _BenchmarkMessage.ofLength(60);
    await tester.pumpWidget(host(message, messageEvent(message)));

    expect(find.byType(UnderlineText), findsNWidgets(60));
    expect(find.byType(HtmlMessage), findsOneWidget);
  });

  testWidgets('rebuild benchmark: 60-word message, 40 timeline-style '
      'rebuilds', (tester) async {
    final message = _BenchmarkMessage.ofLength(60);
    final event = messageEvent(message);

    const iterations = 40;

    // Fresh-wrapper variant first (biases any residual warm-up advantage
    // AGAINST the cached variant): a new wrapper per pump is what every
    // timeline rebuild paid before the ChatController wrapper cache
    // (#8393 stage 2), re-parsing the representation/token JSON each time.
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(host(message, messageEvent(message)));
    }
    final freshStopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await tester.pumpWidget(host(message, messageEvent(message)));
    }
    freshStopwatch.stop();

    // Shared-wrapper variant: what the timeline pays with the cache.
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(host(message, event));
    }
    final sharedStopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await tester.pumpWidget(host(message, event));
    }
    sharedStopwatch.stop();

    String ms(Stopwatch s) =>
        (s.elapsedMicroseconds / iterations / 1000.0).toStringAsFixed(2);
    // ignore: avoid_print
    print(
      'HTML_MESSAGE_BENCHMARK 60 tokens x $iterations rebuilds: '
      'fresh-wrapper ${ms(freshStopwatch)} ms/rebuild, '
      'shared-wrapper ${ms(sharedStopwatch)} ms/rebuild',
    );

    expect(find.byType(UnderlineText), findsNWidgets(60));
  });
}
