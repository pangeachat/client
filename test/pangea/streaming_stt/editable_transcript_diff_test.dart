import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/editable_transcript.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';

void main() {
  test('constructing from a settled final seeds controller.diffBase', () {
    final t = EditableTranscript(originalAsrText: 'hola mundo');
    expect(t.controller.diffBase, 'hola mundo');
    t.dispose();
  });

  test('settle + late-final re-settle keep diffBase == originalAsrText', () {
    final t = EditableTranscript.fromRecording();
    t.beginFinalizing();
    t.settle('hola mundo');
    expect(t.controller.diffBase, 'hola mundo');
    t.dispose();
  });

  test('applyStreamingUpdate final re-settle updates diffBase', () {
    final t = EditableTranscript(originalAsrText: 'ola');
    t.applyStreamingUpdate(
      const SttPartial(
        transcript: 'hola',
        words: <SttWord>[],
        isFinal: true,
        speechFinal: false,
      ),
    );
    expect(t.controller.diffBase, 'hola');
    t.dispose();
  });

  testWidgets('buildTextSpan colors the live diff against diffBase', (
    tester,
  ) async {
    final c = EditableTranscriptController(text: 'hola mundo')
      ..diffBase = 'ola mundo';
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = c.buildTextSpan(
              context: context,
              style: const TextStyle(),
              withComposing: false,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    final spans = span.children!.cast<TextSpan>();
    final changed = spans.firstWhere((s) => s.text == 'hola');
    expect(changed.style?.decorationColor, AppConfig.warning);
    c.dispose();
  });

  testWidgets('buildTextSpan is plain text when diffBase is empty', (
    tester,
  ) async {
    final c = EditableTranscriptController(text: 'hola');
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = c.buildTextSpan(
              context: context,
              style: const TextStyle(),
              withComposing: false,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(span.children, isNull);
    expect(span.text, 'hola');
    c.dispose();
  });
}
