import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/local_spell_check.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/match_rule_id_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';

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

  group('LocalSpellCheck.resolveLocale', () {
    // Exactly what UITextChecker.availableLanguages returned on an iOS 18.3
    // simulator: underscores, some languages bare, others only regional.
    const iosAvailable = [
      'en_US',
      'lt_LT',
      'nb_NO',
      'ga_IE',
      'sl_SI',
      'cs_CZ',
      'hu_HU',
      'da_DK',
      'en_CA',
      'en_SG',
      'bg_BG',
      'ar',
      'es_MX',
      'fi_FI',
      'es_ES',
      'hi',
      'he_IL',
      'is_IS',
      'it_IT',
      'nl_NL',
      'nn',
      'ro_RO',
      'te',
      'uk_UA',
      'vi_VN',
      'ru_RU',
      'en_GB',
      'fr_FR',
      'pa',
      'en_ZA',
      'en_AU',
      'de_DE',
      'pt_BR',
      'pl_PL',
      'el_GR',
      'en_NZ',
      'id_ID',
      'sv_SE',
      'tr_TR',
      'ars',
      'en_IN',
      'pt_PT',
    ];

    test('a bare target language resolves to a regional dictionary', () {
      // The bug this exists for: every supported L2 is a bare code, and iOS
      // returns null for a tag it does not list.
      expect(
        LocalSpellCheck.resolveLocale('es', iosAvailable)?.toLanguageTag(),
        'es-MX',
      );
      expect(
        LocalSpellCheck.resolveLocale('fr', iosAvailable)?.toLanguageTag(),
        'fr-FR',
      );
    });

    test('a language listed bare stays bare', () {
      expect(
        LocalSpellCheck.resolveLocale('ar', iosAvailable)?.toLanguageTag(),
        'ar',
      );
    });

    test('an exact regional match wins over a sibling region', () {
      // pt_BR is listed before pt_PT, so only an exact match gets pt-PT —
      // which matters because the two spell differently.
      expect(
        LocalSpellCheck.resolveLocale('pt-PT', iosAvailable)?.toLanguageTag(),
        'pt-PT',
      );
      expect(
        LocalSpellCheck.resolveLocale('pt', iosAvailable)?.toLanguageTag(),
        'pt-BR',
      );
    });

    test('underscores in the target are accepted too', () {
      expect(
        LocalSpellCheck.resolveLocale('pt_PT', iosAvailable)?.toLanguageTag(),
        'pt-PT',
      );
    });

    test('a language the device cannot check resolves to null', () {
      // Skips the pass rather than asking and getting null back.
      expect(LocalSpellCheck.resolveLocale('zu', iosAvailable), isNull);
      expect(LocalSpellCheck.resolveLocale('cy', iosAvailable), isNull);
    });

    test('an unknown device list falls back to asking directly', () {
      // Empty means the platform could not tell us, not that nothing works —
      // Android may still answer a bare code.
      expect(
        LocalSpellCheck.resolveLocale('es', const [])?.toLanguageTag(),
        'es',
      );
    });

    test(
      'a target with a region the device lacks falls back to the language',
      () {
        expect(
          LocalSpellCheck.resolveLocale('es-AR', iosAvailable)?.toLanguageTag(),
          'es-MX',
        );
      },
    );
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

  group('localSpansToSpanData guards', () {
    test('drops a span overlapping one already taken', () {
      // Replacements apply against a shifting string, so an overlapping span
      // would splice into the previous one's output.
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 0, end: 6), ['hello']),
        SuggestionSpan(TextRange(start: 3, end: 9), ['there']),
      ], 'helllo yz');

      expect(spans, hasLength(1));
      expect(spans.single.errorSpan, 'helllo');
    });

    test('drops a suggestion identical to the flagged word', () {
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 0, end: 6), ['Mumbai']),
      ], 'Mumbai es bonito');

      expect(spans, isEmpty);
    });

    test('drops a span whose first suggestion echoes the input', () {
      // selectBestChoice takes index 0, so an echo there makes the span a
      // no-op even when a usable alternative follows it.
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['wrold', 'world']),
      ], 'wrold');

      expect(spans, isEmpty);
    });

    test('orders spans by position regardless of input order', () {
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 6, end: 11), ['hello']),
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ], 'wrold hlelo');

      expect(spans.map((s) => s.offset), [0, 6]);
    });
  });

  group('IgcController.addLocalSpellMatches', () {
    late IgcController controller;

    setUp(() {
      controller = IgcController((_) {}, () {});
    });

    test('adds open matches — spelling is never applied for the learner', () {
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 7, end: 12), ['world']),
      ], 'Hello, wrold');

      expect(controller.addLocalSpellMatches(spans, 'Hello, wrold'), isTrue);
      expect(controller.matches, hasLength(1));
      expect(
        controller.matches.single.updatedMatch.status,
        PangeaMatchStatusEnum.open,
      );
      expect(controller.openMatches, hasLength(1));
      // Highlights are split on this, so it must be the text the spans
      // were found in.
      expect(controller.currentText, 'Hello, wrold');
    });

    test('tags matches so the server response can replace them', () {
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ], 'wrold');
      controller.addLocalSpellMatches(spans, 'wrold');

      expect(
        controller.matches.single.updatedMatch.match.rule?.id,
        MatchRuleIdModel.localSpellCheck,
      );
    });

    test('reports nothing added when the device finds nothing', () {
      expect(controller.addLocalSpellMatches(const [], 'hello'), isFalse);
      expect(controller.matches, isEmpty);
      expect(controller.currentText, isNull);
    });
  });

  group('IgcController.clearAfterFailedRequest', () {
    late IgcController controller;

    setUp(() {
      controller = IgcController((_) {}, () {});
    });

    test('keeps the device spelling when the server is unreachable', () {
      final spans = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ], 'wrold');
      controller.addLocalSpellMatches(spans, 'wrold');

      controller.clearAfterFailedRequest();

      // Offline is when this is the only writing assistance available.
      expect(controller.localSpellMatches, hasLength(1));
      expect(controller.currentText, 'wrold');
    });

    test('still clears everything when there is no local spelling', () {
      expect(controller.addLocalSpellMatches(const [], 'hello'), isFalse);

      controller.clearAfterFailedRequest();

      expect(controller.matches, isEmpty);
      expect(controller.currentText, isNull);
    });

    test('does not keep server matches', () {
      final local = localSpansToSpanData(const [
        SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
      ], 'wrold es');
      controller.addLocalSpellMatches(local, 'wrold es');
      controller.matches.add(
        PangeaMatchState(
          match: SpanData(
            message: null,
            shortMessage: null,
            choices: [
              SpanChoice(value: 'está', type: SpanChoiceTypeEnum.suggestion),
            ],
            offset: 6,
            length: 2,
            fullText: 'wrold es',
            type: ReplacementTypeEnum.verbConjugation,
            rule: null,
          ),
          status: PangeaMatchStatusEnum.open,
          original: PangeaMatch(
            match: SpanData(
              message: null,
              shortMessage: null,
              choices: null,
              offset: 6,
              length: 2,
              fullText: 'wrold es',
              type: ReplacementTypeEnum.verbConjugation,
              rule: null,
            ),
            status: PangeaMatchStatusEnum.open,
          ),
        ),
      );

      controller.clearAfterFailedRequest();

      expect(controller.matches, hasLength(1));
      expect(
        controller.matches.single.updatedMatch.match.rule?.id,
        MatchRuleIdModel.localSpellCheck,
      );
    });
  });
}
