import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/pangea/tokens/stt_transcript_tokens.dart';
import 'package:fluffychat/pangea/tokens/tokens_util.dart';

/// Widget-level coverage for [SttTranscriptTokens].
///
/// The widget has two branches. The non-empty-tokens branch calls
/// `TokensUtil.getNewTokens` which in turn reads
/// `MatrixState.pangeaController.matrixState.analyticsDataService` — a
/// process-global singleton not initialized under `flutter test`. Covering
/// that branch requires bringing up a fake `MatrixState`, which is out of
/// scope for this change; it's covered by the TO TEST section on issue
/// #1963 (which exercises the real app on real payloads).
///
/// The empty-tokens branch has no singleton dependency and is tested here
/// as a smoke test to guard against a regression in the fallback render.
void main() {
  testWidgets(
    'SttTranscriptTokens renders plain Text when there are no STT tokens',
    (tester) async {
      final model = SpeechToTextResponseModel.fromJson({
        'results': [
          {
            'transcripts': [
              {
                'confidence': 100,
                'lang_code': 'en',
                'stt_tokens': <Map<String, dynamic>>[],
                'transcript': 'hello world',
                'words_per_hr': null,
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SttTranscriptTokens(eventId: 'test', model: model),
          ),
        ),
      );

      expect(find.text('hello world'), findsOneWidget);
    },
  );

  // ---------------------------------------------------------------------
  // Rendering-contract integration test.
  //
  // Reproduces the exact RichText structure that `SttTranscriptTokens`
  // builds — TextSpan per gap, WidgetSpan per token, tap handler on the
  // token's `GestureDetector`. We skip `TokensUtil.getNewTokens` because
  // that reads the `MatrixState` singleton; everything else matches the
  // real widget, so any regression in how `getGlobalTokenPositions`
  // output interacts with `.characters.skip/take` would break this test.
  // ---------------------------------------------------------------------

  Widget buildTranscript(
    String transcript,
    List<PangeaToken> tokens,
    void Function(PangeaToken) onTap,
  ) {
    final positions = TokensUtil.instance.getGlobalTokenPositions(
      tokens,
      transcript: transcript,
    );
    final chars = transcript.characters;

    return MaterialApp(
      home: Scaffold(
        body: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black),
            children: positions.map<InlineSpan>((p) {
              final text = chars
                  .skip(p.startIndex)
                  .take(p.endIndex - p.startIndex)
                  .toString();
              if (p.token == null) {
                return TextSpan(text: text);
              }
              final token = p.token!;
              return WidgetSpan(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => onTap(token),
                  child: Text(text),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  PangeaToken makeToken({
    required String content,
    required int offset,
    String pos = 'NOUN',
  }) {
    return PangeaToken(
      text: PangeaTokenText.fromJson({'content': content, 'offset': offset}),
      lemma: Lemma(text: content, saveVocab: false, form: content),
      pos: pos,
      morph: const {},
    );
  }

  testWidgets(
    'Punjabi "ਕਰਕੇ" renders as a single fully tappable WidgetSpan (issue #1963)',
    (tester) async {
      const transcript = 'ਕਿਰਪਾ ਕਰਕੇ';
      final tokens = [
        makeToken(content: 'ਕਿਰਪਾ', offset: 0),
        makeToken(content: 'ਕਰਕੇ', offset: 6),
      ];
      final tapped = <PangeaToken>[];

      await tester.pumpWidget(buildTranscript(transcript, tokens, tapped.add));

      // Both words rendered in full, not truncated to a single character.
      expect(find.text('ਕਿਰਪਾ'), findsOneWidget);
      expect(find.text('ਕਰਕੇ'), findsOneWidget);

      // Tap the second word; the correct token fires.
      await tester.tap(find.text('ਕਰਕੇ'));
      expect(tapped, hasLength(1));
      expect(tapped.first.text.content, 'ਕਰਕੇ');
    },
  );

  testWidgets('Bangla + emoji: tapping the emoji fires the emoji token', (
    tester,
  ) async {
    const transcript = 'আমি এখানেই আছি 😄';
    final tokens = [
      makeToken(content: 'আমি', offset: 0),
      makeToken(content: 'এখানেই', offset: 4),
      makeToken(content: 'আছি', offset: 11),
      makeToken(content: '😄', offset: 15),
    ];
    final tapped = <PangeaToken>[];

    await tester.pumpWidget(buildTranscript(transcript, tokens, tapped.add));

    expect(find.text('এখানেই'), findsOneWidget);
    expect(find.text('😄'), findsOneWidget);

    await tester.tap(find.text('😄'));
    expect(tapped.single.text.content, '😄');
  });

  testWidgets('ASCII regression: tapping each word fires the correct token', (
    tester,
  ) async {
    const transcript = 'hello world';
    final tokens = [
      makeToken(content: 'hello', offset: 0),
      makeToken(content: 'world', offset: 6),
    ];
    final tapped = <PangeaToken>[];

    await tester.pumpWidget(buildTranscript(transcript, tokens, tapped.add));

    await tester.tap(find.text('hello'));
    await tester.tap(find.text('world'));
    expect(tapped.map((t) => t.text.content).toList(), ['hello', 'world']);
  });

  testWidgets('ZWJ family emoji renders as one tappable unit', (tester) async {
    const transcript = 'my family 👨‍👩‍👧';
    final tokens = [
      makeToken(content: 'my', offset: 0, pos: 'PRON'),
      makeToken(content: 'family', offset: 3),
      makeToken(content: '👨‍👩‍👧', offset: 10),
    ];
    final tapped = <PangeaToken>[];

    await tester.pumpWidget(buildTranscript(transcript, tokens, tapped.add));

    expect(find.text('👨‍👩‍👧'), findsOneWidget);
    await tester.tap(find.text('👨‍👩‍👧'));
    expect(tapped.single.text.content, '👨‍👩‍👧');
  });
}
