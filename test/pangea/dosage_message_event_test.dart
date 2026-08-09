import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/dosage/dosage_message_event.dart';

/// Unit tests for the dosage message-envelope model derivation + serialization.
void main() {
  test('uses the provided token count when the message was tokenized', () {
    final event = DosageMessageEvent.fromSentMessage(
      roomId: '!r:x',
      msgId: '\$e:x',
      ts: DateTime.utc(2026, 1, 1),
      body: 'the quick brown fox',
      tokenCount: 12,
      langCode: 'fr',
    );
    expect(event.tokenCount, 12);
    expect(event.langCode, 'fr');
  });

  test('falls back to a whitespace token count when not tokenized', () {
    final event = DosageMessageEvent.fromSentMessage(
      roomId: '!r:x',
      msgId: '\$e:x',
      ts: DateTime.utc(2026, 1, 1),
      body: '  hola   mundo  bonito ',
      tokenCount: null,
      langCode: null,
    );
    // Trimmed, split on runs of whitespace => 3 tokens.
    expect(event.tokenCount, 3);
    expect(event.charCount, '  hola   mundo  bonito '.length);
  });

  test('whitespace fallback of an empty/blank body is zero', () {
    expect(DosageMessageEvent.whitespaceTokenCount(''), 0);
    expect(DosageMessageEvent.whitespaceTokenCount('   '), 0);
  });

  test('does not invent a language: lang_code stays null when unknown', () {
    final event = DosageMessageEvent.fromSentMessage(
      roomId: '!r:x',
      msgId: '\$e:x',
      ts: DateTime.utc(2026, 1, 1),
      body: 'pasted text',
      tokenCount: 2,
      langCode: null,
    );
    expect(event.langCode, isNull);
    expect(event.toJson()['lang_code'], isNull);
  });

  test('clamps token_count and char_count to the server ceilings', () {
    final event = DosageMessageEvent.fromSentMessage(
      roomId: '!r:x',
      msgId: '\$e:x',
      ts: DateTime.utc(2026, 1, 1),
      body: 'a' * 70000,
      tokenCount: 9999,
      langCode: 'en',
    );
    expect(event.tokenCount, DosageMessageEvent.maxTokenCount);
    expect(event.charCount, DosageMessageEvent.maxCharCount);
  });

  test(
    'toJson carries EXACTLY the contract keys — no lang_source, no sender',
    () {
      final json = DosageMessageEvent.fromSentMessage(
        roomId: '!r:x',
        msgId: '\$e:x',
        ts: DateTime.utc(2026, 1, 1, 9, 30),
        body: 'hi',
        tokenCount: 1,
        langCode: 'en',
      ).toJson();

      expect(json.keys.toSet(), {
        'room_id',
        'msg_id',
        'ts',
        'token_count',
        'char_count',
        'lang_code',
      });
      expect(json.containsKey('lang_source'), isFalse);
      expect(json.containsKey('sender'), isFalse);
      expect(json['ts'], endsWith('Z'), reason: 'UTC-aware ISO-8601');
    },
  );
}
