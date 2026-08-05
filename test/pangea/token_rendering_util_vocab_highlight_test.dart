import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/chat/events/tokens/token_rendering_util.dart';

/// Coverage for the shared target-vocab highlight helpers used by BOTH the
/// typed-message renderer (`html_message.dart`) and the STT transcript
/// renderer (`stt_transcript_tokens.dart`). These are the load-bearing
/// decision + gold-wrapping behind issue #7659: spoken target vocab must
/// highlight the same way typed target vocab does. The widgets themselves
/// render tokens through `TokensUtil.getNewTokens`, which reads a process-
/// global `MatrixState` singleton not available under `flutter test` (see
/// stt_transcript_tokens_test.dart) — so the reusable logic is verified
/// here, and the end-to-end render stays in the issue's TO TEST steps.
void main() {
  group('TokenRenderingUtil.isVocabHighlight', () {
    test('false when the room has no activity plan (null lemma set)', () {
      expect(TokenRenderingUtil.isVocabHighlight('hola', null), isFalse);
    });

    test('true when the lemma is a target vocab word', () {
      expect(
        TokenRenderingUtil.isVocabHighlight('hola', {'hola', 'gracias'}),
        isTrue,
      );
    });

    test('false when the lemma is not a target vocab word', () {
      expect(
        TokenRenderingUtil.isVocabHighlight('adios', {'hola', 'gracias'}),
        isFalse,
      );
    });

    test('case-insensitive — spoken casing must not defeat the match', () {
      // vocabLemmas is pre-lower-cased by callers; the token lemma may not be.
      expect(TokenRenderingUtil.isVocabHighlight('Hola', {'hola'}), isTrue);
    });

    test('false for empty lemma even against a non-empty set', () {
      expect(TokenRenderingUtil.isVocabHighlight('', {'hola'}), isFalse);
    });
  });

  group('TokenRenderingUtil.vocabHighlight', () {
    testWidgets('returns the child unchanged when highlight is false', (
      tester,
    ) async {
      const child = Text('hola');
      final result = TokenRenderingUtil.vocabHighlight(
        highlight: false,
        child: child,
      );

      expect(identical(result, child), isTrue);
    });

    testWidgets('wraps the child in the gold highlight when highlight is true', (
      tester,
    ) async {
      final result = TokenRenderingUtil.vocabHighlight(
        highlight: true,
        child: const Text('hola'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: result)),
        ),
      );

      // The spoken word is still shown...
      expect(find.text('hola'), findsOneWidget);

      // ...inside a DecoratedBox tinted with the gold vocab colour, matching
      // the typed-message highlight in html_message.dart.
      final decoratedBox = tester.widget<DecoratedBox>(
        find.ancestor(
          of: find.text('hola'),
          matching: find.byType(DecoratedBox),
        ),
      );
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.color, AppConfig.gold.withAlpha(50));
      // Pin the gold caller's full geometry so the shared-helper extraction is
      // provably pixel-identical for the real existing caller, not just color.
      expect(decoration.borderRadius, BorderRadius.circular(12));
      final padding = tester.widget<Padding>(
        find
            .ancestor(of: find.text('hola'), matching: find.byType(Padding))
            .first,
      );
      expect(padding.padding, const EdgeInsets.symmetric(horizontal: 4));
    });

    testWidgets(
      'de-hardcoded + pixel-identical box: color, 12px radius, 4px h-padding',
      (tester) async {
        final result = TokenRenderingUtil.vocabHighlight(
          highlight: true,
          color: AppConfig.warning,
          child: const Text('hola'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Center(child: result)),
          ),
        );
        final box = tester.widget<DecoratedBox>(
          find.ancestor(
            of: find.text('hola'),
            matching: find.byType(DecoratedBox),
          ),
        );
        final decoration = box.decoration as BoxDecoration;
        // Full geometry parity with the pre-extraction vocabHighlight
        // (token_rendering_util.dart:65-72): tint alpha 50, radius 12, pad 4.
        expect(decoration.color, AppConfig.warning.withAlpha(50));
        expect(decoration.borderRadius, BorderRadius.circular(12));
        final padding = tester.widget<Padding>(
          find
              .ancestor(of: find.text('hola'), matching: find.byType(Padding))
              .first,
        );
        expect(padding.padding, const EdgeInsets.symmetric(horizontal: 4));
      },
    );
  });
}
