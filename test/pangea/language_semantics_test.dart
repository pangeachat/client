import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/widgets/language_semantics.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/routes/chat/message_content.dart';
import 'package:fluffychat/routes/chat/toolbar/message_toolbar_host.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #9266 — text not in the UI language carries its own language, so a screen
/// reader reads it in that language's voice (WCAG 3.1.2).

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

/// Every node in the tree as (label, locale).
List<(String, Locale?)> _nodes(WidgetTester tester) {
  final out = <(String, Locale?)>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    out.add((data.label, data.locale));
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return out;
}

Locale? _localeOf(WidgetTester tester, String label) =>
    _nodes(tester).singleWhere((n) => n.$1 == label).$2;

void main() {
  group('LanguageSemantics', () {
    Future<void> pump(WidgetTester tester, String? langCode) =>
        tester.pumpWidget(
          MaterialApp(
            home: Semantics(
              label: 'Anna',
              child: Column(
                children: [
                  LanguageSemantics(
                    langCode: langCode,
                    child: const Text('hola'),
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('marks the text, and not the label beside it', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, 'es-MX');

      expect(_localeOf(tester, 'hola'), const Locale('es'));
      expect(
        _localeOf(tester, 'Anna'),
        isNull,
        reason: 'the language must not reach the sender name',
      );
      semantics.dispose();
    });

    testWidgets('an unknown language leaves the text unmarked', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final langCode in [null, '', 'unk']) {
        await pump(tester, langCode);
        expect(
          _nodes(tester).where((n) => n.$2 != null),
          isEmpty,
          reason: '"$langCode" must not be guessed',
        );
        expect(
          _nodes(tester).any((n) => n.$1 == 'Anna\nhola'),
          isTrue,
          reason: 'unmarked text stays in the node it merged into',
        );
      }
      semantics.dispose();
    });

    test('labelWithPart marks only the part', () {
      final label = LanguageSemantics.labelWithPart(
        'bien, Seeds, new words',
        part: 'bien',
        langCode: 'es',
      );
      final attribute = label.attributes.single as LocaleStringAttribute;
      expect(attribute.range, const TextRange(start: 0, end: 4));
      expect(attribute.locale, const Locale('es'));

      expect(
        LanguageSemantics.labelWithPart(
          'Deleted: bien',
          part: 'bien',
          langCode: 'unk',
        ).attributes,
        isEmpty,
      );
      expect(
        LanguageSemantics.labelWithPart(
          'Deleted: bien',
          part: 'mal',
          langCode: 'es',
        ).attributes,
        isEmpty,
      );
    });
  });

  group('MessageContent', () {
    late Client client;
    late Room room;
    late Timeline timeline;

    setUp(() async {
      MatrixState.pangeaController = FakePangeaController();
      client = await getTestClient();
      // Quiesce the sync loop: its retry timers would trip the binding's
      // pending-timer invariant.
      client.backgroundSync = false;
      client.abortSync();
      room = Room(id: '!lang:fakeServer.notExisting', client: client);
      timeline = await room.getTimeline();
    });

    tearDown(() async {
      timeline.cancelSubscriptions();
      await client.dispose();
    });

    PangeaMessageEvent messageEvent(String langCode) {
      const words = ['buenos', 'días'];
      final tokens = <PangeaToken>[];
      var offset = 0;
      for (final word in words) {
        tokens.add(
          PangeaToken.fromJson({
            'text': {'content': word, 'offset': offset, 'length': word.length},
            'lemma': {'text': word, 'save_vocab': true, 'form': word},
            'pos': 'NOUN',
            'morph': <String, dynamic>{},
          }),
        );
        offset += word.length + 1;
      }
      return PangeaMessageEvent(
        event: Event(
          type: EventTypes.Message,
          eventId: r'$lang:fakeServer.notExisting',
          senderId: '@lang:fakeServer.notExisting',
          originServerTs: DateTime.now(),
          content: {
            'msgtype': 'm.text',
            'body': words.join(' '),
            MessageConstants.tokensSent: PangeaMessageTokens(
              tokens: tokens,
              detections: [
                LanguageDetectionModel(langCode: langCode, confidence: 1),
              ],
            ).toJson(),
          },
          room: room,
        ),
        timeline: timeline,
        ownMessage: true,
      );
    }

    Future<void> pump(
      WidgetTester tester,
      PangeaMessageEvent event, {
      bool markLanguage = true,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageContent(
            event.event,
            textColor: Colors.black,
            linkColor: Colors.blue,
            borderRadius: BorderRadius.zero,
            timeline: timeline,
            selected: false,
            pangeaMessageEvent: event,
            controller: _FakeToolbarHost(room),
            onTokenClick: (_) {},
            markLanguage: markLanguage,
          ),
        ),
      ),
    );

    testWidgets('the text and each of its words carry its language', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, messageEvent('es'));

      final nodes = _nodes(tester);
      final text = nodes.where((n) => n.$1.startsWith('buenos días'));
      expect(text, isNotEmpty, reason: 'the message text is read');
      expect(text.map((n) => n.$2), everyElement(const Locale('es')));
      expect(_localeOf(tester, 'buenos'), const Locale('es'));
      expect(_localeOf(tester, 'días'), const Locale('es'));
      semantics.dispose();
    });

    testWidgets('an unknown language is not guessed', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, messageEvent('unk'));

      expect(_nodes(tester).where((n) => n.$2 != null), isEmpty);
      semantics.dispose();
    });

    testWidgets('a host that marks the language itself gets no inner node', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, messageEvent('es'), markLanguage: false);

      expect(_nodes(tester).where((n) => n.$2 != null), isEmpty);
      semantics.dispose();
    });
  });
}
