import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/transcript_tokens.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';

/// The rule these pin: a transcript is ALWAYS readable. Tokenizing its words is
/// an enhancement (#8797), so while the tokenizer is pending, and on any failure
/// or empty result, the text stays plain, selectable text -- never blank, and
/// never gated on a network round trip. The tokenized clickable render itself
/// stands up the app's overlay plane (`MatrixState.pAnyState`) and is verified
/// against a real transcript rather than here.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('TranscriptTokens fallback', () {
    testWidgets('shows plain, selectable text while the tokenizer is pending', (
      tester,
    ) async {
      final pending = Completer<TokensResponseModel?>();
      await tester.pumpWidget(
        host(
          TranscriptTokens(
            text: 'hola mundo',
            langCode: 'es',
            tokenize: (_, _) => pending.future,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('hola mundo'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);

      pending.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('a failed tokenization stays plain text, never blank', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TranscriptTokens(
            text: 'hola mundo',
            langCode: 'es',
            tokenize: (_, _) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('hola mundo'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('an empty token list stays plain text', (tester) async {
      await tester.pumpWidget(
        host(
          TranscriptTokens(
            text: 'hola mundo',
            langCode: 'es',
            tokenize: (_, _) async => TokensResponseModel(
              tokens: const [],
              lang: 'es',
              detections: const <LanguageDetectionModel>[],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('hola mundo'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });
  });

  // A malformed tokenizer response must never drop a visible word or crash the
  // render: the widget shows the plain text instead. These reach the tokenized
  // branch (non-empty tokens) and then fail its clean-cover check.
  group('TranscriptTokens stays readable on a malformed tokenization', () {
    PangeaToken tok(String content, int offset) => PangeaToken.fromJson({
      'text': {'content': content, 'offset': offset, 'length': content.length},
      'morph': {'Pos': 'NOUN'},
    });

    TokensResponseModel resp(List<PangeaToken> tokens) => TokensResponseModel(
      tokens: tokens,
      lang: 'es',
      detections: const <LanguageDetectionModel>[],
    );

    testWidgets('a response that does not cover the whole text stays plain', (
      tester,
    ) async {
      // Only the first word of "hola mundo" comes back tokenized.
      await tester.pumpWidget(
        host(
          TranscriptTokens(
            text: 'hola mundo',
            langCode: 'es',
            tokenize: (_, _) async => resp([tok('hola', 0)]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The WHOLE text is shown, not the covered prefix.
      expect(find.text('hola mundo'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('two tokens on one span fall back instead of crashing', (
      tester,
    ) async {
      // Two tokens claiming the same span would overlap the slices and collide
      // one overlay GlobalKey.
      await tester.pumpWidget(
        host(
          TranscriptTokens(
            text: 'hola',
            langCode: 'es',
            tokenize: (_, _) async => resp([tok('hola', 0), tok('hola', 0)]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('hola'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });
  });
}
