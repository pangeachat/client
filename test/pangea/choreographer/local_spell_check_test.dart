import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/local_spell_check.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/match_rule_id_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
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

  group('graphemeOffset', () {
    test('counts plain text one for one', () {
      expect(graphemeOffset('hello', 0), 0);
      expect(graphemeOffset('hello', 3), 3);
      expect(graphemeOffset('hello', 5), 5);
    });

    test('an emoji counts as one grapheme, not its two code units', () {
      const text = 'a👍b';
      expect(text.length, 4); // code units
      expect(graphemeOffset(text, 4), 3); // graphemes
    });

    test('an offset inside a surrogate pair clears the whole pair', () {
      // Code unit 2 is the low surrogate of the emoji, which substring would
      // split. Walking graphemes cannot split it: the offset resolves to the
      // boundary after the emoji rather than into the middle of it.
      expect(graphemeOffset('a👍b', 2), 2);
    });

    test('handles a combining mark as a single grapheme', () {
      // e + combining acute: two code units, one grapheme.
      const text = 'éx';
      expect(graphemeOffset(text, 2), 1);
      expect(graphemeOffset(text, 3), 2);
    });

    test('an offset past the end stops at the last grapheme', () {
      expect(graphemeOffset('a👍', 99), 2);
    });
  });

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

  group('IgcController.addLocalSpellMatches', () {
    const locale = Locale('es');
    late IgcController controller;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      controller = IgcController((_) {}, () {});
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      LocalSpellCheck.service = DefaultSpellCheckService();
    });

    test(
      'adds open matches — spelling is never applied for the learner',
      () async {
        LocalSpellCheck.service = _FakeSpellCheckService(const [
          SuggestionSpan(TextRange(start: 7, end: 12), ['world']),
        ]);

        expect(
          await controller.addLocalSpellMatches('Hello, wrold', locale),
          isTrue,
        );
        expect(controller.matches, hasLength(1));
        expect(
          controller.matches.single.updatedMatch.status,
          PangeaMatchStatusEnum.open,
        );
        expect(controller.openMatches, hasLength(1));
      },
    );

    test('highlights are drawn against the text they were found in', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ]);

      await controller.addLocalSpellMatches('wrold', locale);

      expect(controller.currentText, 'wrold');
    });

    test('tags matches so the server response can replace them', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ]);

      await controller.addLocalSpellMatches('wrold', locale);

      expect(
        controller.matches.single.updatedMatch.match.rule?.id,
        MatchRuleIdModel.localSpellCheck,
      );
    });

    test('reports nothing added when the device finds nothing', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const []);

      expect(await controller.addLocalSpellMatches('hello', locale), isFalse);
      expect(controller.matches, isEmpty);
      expect(controller.currentText, isNull);
    });
  });
}
