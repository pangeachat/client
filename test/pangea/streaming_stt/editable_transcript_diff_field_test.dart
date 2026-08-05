import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/editable_transcript.dart';
import 'package:fluffychat/routes/chat/recording_input_row.dart';

void main() {
  Widget host(EditableTranscriptController c) => MaterialApp(
    home: Scaffold(body: EditableTranscriptDiffField(controller: c)),
  );

  testWidgets('shows only the replaced source word struck through', (
    tester,
  ) async {
    final c = EditableTranscriptController(
      text: 'Hallo! Mir geht sehr hart gutuh.',
    )..diffBase = 'Hallo! Mir geht sehr hart gut.';
    await tester.pumpWidget(host(c));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('gut.'), findsOneWidget);
    expect(find.text('Hallo! Mir geht sehr hart gut.'), findsNothing);
    final source = tester.widget<Text>(find.text('gut.'));
    expect(source.style?.decoration, TextDecoration.lineThrough);
    c.dispose();
  });

  testWidgets('no struck original for a clean buffer (text == diffBase)', (
    tester,
  ) async {
    final c = EditableTranscriptController(text: 'hola mundo')
      ..diffBase = 'hola mundo';
    await tester.pumpWidget(host(c));
    expect(find.byKey(const Key('stt-editor-original-changes')), findsNothing);
    c.dispose();
  });
}
