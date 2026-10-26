import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/example_message_util.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import '../get_test_client.dart';

/// Tokens for [sentence], split on spaces with a trailing "." as its own
/// token, offsets counted from the sentence's start as the tokenizer does.
List<PangeaToken> _tokens(String sentence) {
  final tokens = <PangeaToken>[];
  var offset = 0;
  for (final raw in sentence.split(' ')) {
    final stop = raw.endsWith('.');
    final word = stop ? raw.substring(0, raw.length - 1) : raw;
    tokens.add(_token(word, offset));
    if (stop) tokens.add(_token('.', offset + word.length));
    offset += raw.length + 1;
  }
  return tokens;
}

PangeaToken _token(String text, int offset) => PangeaToken(
  text: PangeaTokenText(content: text, offset: offset, length: text.length),
  lemma: Lemma(text: text.toLowerCase(), saveVocab: true, form: text),
  pos: 'NOUN',
  morph: const {},
);

const _sentence = 'Puede ser difícil saber qué está pasando.';
const _quoted = 'Ahora, construyan una política interna.';

/// An example is built only from tokens that fit the text it shows: a token
/// read at the wrong offset stitches the words into the wrong characters
/// (practice-exercises.instructions.md, "Speaking practice").
void main() {
  group('tokensFitText', () {
    test('tokens for the sentence alone do not fit a text with a paragraph '
        'before it', () {
      // The shape the read-aloud bubble garbled: a reply's quote, then the
      // sentence, with tokens counted from the sentence's own start.
      const text =
          '> <@test:fakeServer.notExisting> $_quoted\n\n'
          '$_sentence';
      expect(ExampleMessageUtil.tokensFitText(_tokens(_sentence), text), false);
    });

    test('tokens fit the text they were computed for', () {
      expect(
        ExampleMessageUtil.tokensFitText(_tokens(_sentence), _sentence),
        true,
      );
    });

    test('tokens offset past a prefix they skip still fit', () {
      const prefix = '@test hola\n\n';
      final tokens = [
        for (final t in _tokens(_sentence))
          _token(t.text.content, t.text.offset + prefix.length),
      ];
      expect(
        ExampleMessageUtil.tokensFitText(tokens, '$prefix$_sentence'),
        true,
      );
    });

    test('a token running past the end of the text does not fit', () {
      expect(
        ExampleMessageUtil.tokensFitText(_tokens(_sentence), 'Puede ser'),
        false,
      );
    });
  });

  group('a reply sent with its tokens', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await getTestClient();
      // A room and transaction id the fake server answers a send for.
      room = Room(id: '!1234:example.com', client: client);
      client.rooms.add(room);
    });

    test('reads back as the text its tokens were computed for', () async {
      final parent = Event(
        type: EventTypes.Message,
        eventId: r'$parent:fakeServer.notExisting',
        senderId: client.userID!,
        originServerTs: DateTime.now(),
        content: {'msgtype': MessageTypes.Text, 'body': _quoted},
        room: room,
      );
      final eventId = await room.pangeaSendTextEvent(
        _sentence,
        txid: '1234',
        inReplyTo: parent,
        tokensSent: PangeaMessageTokens(
          tokens: _tokens(_sentence),
          detections: const [
            LanguageDetectionModel(langCode: 'es', confidence: 1),
          ],
        ),
      );
      final event = await client.getRoomById(room.id)!.getEventById(eventId!);

      // The SDK sends a reply's quote in front of the typed text.
      expect(event!.body, isNot(_sentence));
      expect(event.body, endsWith('\n\n$_sentence'));

      final sent = PangeaMessageEvent(
        event: event,
        timeline: await room.getTimeline(),
        ownMessage: true,
      ).originalSent!;
      expect(sent.text, _sentence);
      expect(ExampleMessageUtil.tokensFitText(sent.tokens!, sent.text), true);
    });
  });
}
