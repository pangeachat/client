import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/widgets/choice_array.dart';

/// Writing assistance's Listen mode (#8562). A learner who knows a language by
/// ear taps a choice to hear it — and used to have that tap answer for them,
/// with a second tap to replay putting the wrong word in their message.
/// In Listen mode a tap plays and selects nothing, however many times it lands.
void main() {
  late List<String> selected;

  setUp(() => selected = []);

  Future<void> pumpChoices(
    WidgetTester tester, {
    required bool listenMode,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChoicesArray<String>(
          choices: [
            Choice(value: 'μιλάω'),
            Choice(value: 'μιλάει'),
          ],
          onPressed: (value, index) => selected.add(value),
          selectedChoiceIndex: null,
          roomId: '!room:server',
          // The audio path reaches the live TTS controller and the signed-in
          // user; this test is about what a tap selects, not what it plays.
          enableAudio: false,
          getDisplayCopy: (value) => value,
          id: 'listen-mode-test',
          listenMode: listenMode,
        ),
      ),
    ),
  );

  group('ChoicesArray listen mode', () {
    testWidgets('a tap selects the choice when listen mode is off', (
      tester,
    ) async {
      await pumpChoices(tester, listenMode: false);
      await tester.tap(find.text('μιλάει'));
      await tester.pump();

      expect(selected, ['μιλάει']);
    });

    testWidgets('a tap selects nothing while listen mode is on', (
      tester,
    ) async {
      await pumpChoices(tester, listenMode: true);
      await tester.tap(find.text('μιλάει'));
      await tester.pump();

      expect(selected, isEmpty);
    });

    testWidgets('repeat taps in listen mode still select nothing', (
      tester,
    ) async {
      await pumpChoices(tester, listenMode: true);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('μιλάει'));
        await tester.pump();
      }

      expect(selected, isEmpty);
    });

    testWidgets('leaving listen mode restores selection', (tester) async {
      await pumpChoices(tester, listenMode: true);
      await tester.tap(find.text('μιλάω'));
      await tester.pump();
      expect(selected, isEmpty);

      await pumpChoices(tester, listenMode: false);
      await tester.tap(find.text('μιλάω'));
      await tester.pump();

      expect(selected, ['μιλάω']);
    });
  });
}
