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

  group('IgcController.applyLocalSpellMatches', () {
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

    test('corrects the text so the server request carries the fix', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 7, end: 12), ['world']),
      ]);

      expect(
        await controller.applyLocalSpellMatches('Hello, wrold', locale),
        isTrue,
      );
      expect(controller.currentText, 'Hello, world');
    });

    test('the applied match stays undoable rather than disappearing', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ]);

      await controller.applyLocalSpellMatches('wrold', locale);

      expect(controller.matches, hasLength(1));
      expect(
        controller.matches.single.updatedMatch.status,
        PangeaMatchStatusEnum.automatic,
      );
      expect(controller.openLocalSpellMatches, isEmpty);
    });

    test('tags matches so they are distinguishable from server ones', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ]);

      await controller.applyLocalSpellMatches('wrold', locale);

      expect(
        controller.matches.single.updatedMatch.match.rule?.id,
        MatchRuleIdModel.localSpellCheck,
      );
    });

    test('corrects every misspelling, not just the first', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
        SuggestionSpan(TextRange(start: 6, end: 11), ['hello']),
      ]);

      await controller.applyLocalSpellMatches('wrold hlelo', locale);

      expect(controller.currentText, 'world hello');
      expect(controller.matches, hasLength(2));
    });

    test('an applied correction survives a failed request', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ]);
      await controller.applyLocalSpellMatches('wrold', locale);

      controller.clearAfterFailedRequest();

      // The composer still shows 'world', so the match that changed it has to
      // stay or the learner cannot undo it.
      expect(controller.currentText, 'world');
      expect(controller.appliedLocalSpellMatches, hasLength(1));
    });

    test('a failed request still clears everything else', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const []);
      await controller.applyLocalSpellMatches('hello', locale);

      controller.clearAfterFailedRequest();

      expect(controller.matches, isEmpty);
      expect(controller.currentText, isNull);
    });

    test('leaves the text alone when the device finds nothing', () async {
      LocalSpellCheck.service = _FakeSpellCheckService(const []);

      expect(await controller.applyLocalSpellMatches('hello', locale), isFalse);
      expect(controller.matches, isEmpty);
      expect(controller.currentText, isNull);
    });
  });
}
