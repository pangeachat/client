import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/transcript_diff_view.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';

// These pump under MaterialApp's default (light) theme, so the diff colours
// resolve to the deepened light-theme pair — the bright originals measured
// 1.94:1 and 3.01:1 there, under the 3:1 an underline needs (#8764).
void main() {
  const messageForeground = Color(0xFFF4EEFF);

  SpeechToTextResponseModel transcription(String text) {
    var offset = 0;
    final tokens = <Map<String, dynamic>>[];
    for (final word in text.split(' ')) {
      tokens.add({
        'token': {
          'text': {'content': word, 'offset': offset},
          'lemma': {'text': word, 'save_vocab': true, 'form': word},
          'pos': 'NOUN',
          'morph': <String, dynamic>{},
        },
        'start_time': 0,
        'end_time': 100,
        'confidence': 100,
      });
      offset += word.length + 1;
    }
    return SpeechToTextResponseModel.fromJson({
      'results': [
        {
          'transcripts': [
            {
              'confidence': 100,
              'lang_code': 'es',
              'stt_tokens': tokens,
              'transcript': text,
              'words_per_hr': 120,
            },
          ],
        },
      ],
    });
  }

  Widget host(
    String original,
    String current, {
    void Function(PangeaToken)? onTokenSelected,
  }) => MaterialApp(
    home: Scaffold(
      body: DefaultTextStyle(
        style: const TextStyle(color: messageForeground),
        child: TranscriptDiffView(
          originalAsrText: original,
          transcription: transcription(current),
          eventId: 'event',
          onTokenSelected: onTokenSelected ?? (_) {},
          isTokenSelected: (_) => false,
          newTokensOverride: const <PangeaTokenText>{},
        ),
      ),
    ),
  );

  testWidgets(
    'replacement shows only the edited word orange with its source below',
    (tester) async {
      await tester.pumpWidget(host('ola mundo', 'hola mundo'));

      final changed = tester.widget<UnderlineText>(
        find.byWidgetPredicate(
          (widget) => widget is UnderlineText && widget.text == 'hola',
        ),
      );
      expect(changed.underlineColor, AppConfig.warningDeep);
      final original = tester.widget<Text>(find.text('ola'));
      expect(original.style?.decoration, TextDecoration.lineThrough);
      expect(original.style?.color, messageForeground.withAlpha(160));
      expect(find.text('ola mundo'), findsNothing);

      final changedY = tester
          .getTopLeft(
            find.byWidgetPredicate(
              (widget) => widget is UnderlineText && widget.text == 'hola',
            ),
          )
          .dy;
      final originalY = tester.getTopLeft(find.text('ola')).dy;
      expect(originalY, greaterThan(changedY));
    },
  );

  testWidgets('insertion is orange and has no source word below', (
    tester,
  ) async {
    await tester.pumpWidget(host('hola mundo', 'hola bonito mundo'));
    final inserted = tester.widget<UnderlineText>(
      find.byWidgetPredicate(
        (widget) => widget is UnderlineText && widget.text == 'bonito',
      ),
    );
    expect(inserted.underlineColor, AppConfig.warningDeep);
    expect(find.text('bonito', findRichText: true), findsOneWidget);
  });

  testWidgets('verbatim text has no orange or source-word rows', (
    tester,
  ) async {
    await tester.pumpWidget(host('hola mundo', 'hola mundo'));
    for (final word in ['hola', 'mundo']) {
      final rendered = tester.widget<UnderlineText>(
        find.byWidgetPredicate(
          (widget) => widget is UnderlineText && widget.text == word,
        ),
      );
      expect(rendered.underlineColor, AppConfig.successDeep);
    }
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('edited transcript words retain deployed token tap semantics', (
    tester,
  ) async {
    final tapped = <PangeaToken>[];
    await tester.pumpWidget(
      host('ola mundo', 'hola mundo', onTokenSelected: tapped.add),
    );

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is UnderlineText && widget.text == 'hola',
      ),
    );

    expect(tapped, hasLength(1));
    expect(tapped.single.text.content, 'hola');
    expect(tapped.single.lemma.text, 'hola');
  });
}
