import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/igc/local_spell_check.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';

class _FakeSpellCheckService implements SpellCheckService {
  _FakeSpellCheckService(this.result, {this.error});

  final List<SuggestionSpan>? result;
  final Object? error;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('localSpansToSpanData (pure conversion)', () {
    test('maps a misspelling to a spell span with its suggestions', () {
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 7, end: 12), ['world', 'word']),
      ], 'Hello, wrold!');

      expect(spans, hasLength(1));
      expect(spans.single.type, ReplacementTypeEnum.spell);
      expect(spans.single.offset, 7);
      expect(spans.single.length, 5);
      expect(spans.single.errorSpan, 'wrold');
      expect(spans.single.choices?.map((c) => c.value), ['world', 'word']);
    });

    test('drops a report with no replacements to tap', () {
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 0, end: 5), <String>[]),
      ], 'wrold again');

      expect(spans, isEmpty);
    });

    test('converts code-unit offsets to grapheme offsets past an emoji', () {
      // The emoji is two UTF-16 code units but one grapheme cluster, so the
      // platform's start must land two characters earlier than it reads.
      const text = 'a 👍 wrold';
      final start = text.indexOf('wrold');
      final spans = localSpansToSpanData([
        SuggestionSpan(TextRange(start: start, end: start + 5), const [
          'world',
        ]),
      ], text);

      expect(spans.single.offset, 4);
      expect(spans.single.length, 5);
      expect(spans.single.errorSpan, 'wrold');
    });

    test('drops a range that does not fit the text', () {
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 5, end: 99), ['world']),
        SuggestionSpan(TextRange(start: 3, end: 3), ['world']),
      ], 'short');

      expect(spans, isEmpty);
    });
  });

  group('LocalSpellCheck.spans', () {
    const locale = Locale('es');

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      LocalSpellCheck.service = DefaultSpellCheckService();
    });

    test('is skipped where no device spell checker is reachable', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ]);

      expect(LocalSpellCheck.isSupported, isFalse);
      expect(await LocalSpellCheck.spans('wrold', locale), isEmpty);
    });

    test('falls back to nothing when the device has no dictionary', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      LocalSpellCheck.service = _FakeSpellCheckService(null);

      expect(await LocalSpellCheck.spans('wrold', locale), isEmpty);
    });

    test('falls back to nothing when the lookup fails', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      LocalSpellCheck.service = _FakeSpellCheckService(
        null,
        error: MissingPluginException('no channel'),
      );

      expect(await LocalSpellCheck.spans('wrold', locale), isEmpty);
    });

    test('returns spans on a supported platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ]);

      final spans = await LocalSpellCheck.spans('wrold', locale);
      expect(spans, hasLength(1));
      expect(spans.single.type, ReplacementTypeEnum.spell);
    });

    test('empty text is not sent to the platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      LocalSpellCheck.service = _FakeSpellCheckService(
        null,
        error: StateError('should not be called'),
      );

      expect(await LocalSpellCheck.spans('', locale), isEmpty);
    });
  });
}
