import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/widgets/choice_array.dart';

/// Writing assistance's Listen First mode (#8562, reworked in #8823). A learner
/// who knows a language by ear taps a choice to hear it — and used to have that
/// tap answer for them. In Listen First a single tap only plays; selecting takes
/// a second tap on the same choice inside the double-tap window.
void main() {
  late List<String> selected;

  setUp(() => selected = []);

  Future<void> pumpChoices(
    WidgetTester tester, {
    required bool listenFirstMode,
    String id = 'listen-first-test',
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
          id: id,
          listenFirstMode: listenFirstMode,
        ),
      ),
    ),
  );

  group('ChoicesArray listen first', () {
    testWidgets('a tap selects the choice when listen first is off', (
      tester,
    ) async {
      await pumpChoices(tester, listenFirstMode: false);
      await tester.tap(find.text('μιλάει'));
      await tester.pump();

      expect(selected, ['μιλάει']);
    });

    testWidgets('the first tap selects nothing while listen first is on', (
      tester,
    ) async {
      await pumpChoices(tester, listenFirstMode: true);
      await tester.tap(find.text('μιλάει'));
      await tester.pump();

      expect(selected, isEmpty);
    });

    testWidgets('a second tap inside the window selects the choice', (
      tester,
    ) async {
      await pumpChoices(tester, listenFirstMode: true);
      await tester.tap(find.text('μιλάει'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('μιλάει'));
      await tester.pump();

      expect(selected, ['μιλάει']);
    });

    testWidgets('a second tap after the window only replays', (tester) async {
      await pumpChoices(tester, listenFirstMode: true);
      await tester.tap(find.text('μιλάει'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.tap(find.text('μιλάει'));
      await tester.pump();

      expect(selected, isEmpty);
    });

    testWidgets('the second tap has to be the same choice', (tester) async {
      await pumpChoices(tester, listenFirstMode: true);
      await tester.tap(find.text('μιλάω'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('μιλάει'));
      await tester.pump();

      expect(selected, isEmpty);
    });

    testWidgets('leaving listen first restores single-tap selection', (
      tester,
    ) async {
      await pumpChoices(tester, listenFirstMode: true);
      await tester.tap(find.text('μιλάω'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(selected, isEmpty);

      await pumpChoices(tester, listenFirstMode: false);
      await tester.tap(find.text('μιλάω'));
      await tester.pump();

      expect(selected, ['μιλάω']);
    });

    testWidgets('a choice armed on one match does not carry to the next', (
      tester,
    ) async {
      await pumpChoices(tester, listenFirstMode: true, id: 'match-1');
      await tester.tap(find.text('μιλάω'));
      await tester.pump(const Duration(milliseconds: 50));

      // The card advances: same widget position, different match.
      await pumpChoices(tester, listenFirstMode: true, id: 'match-2');
      await tester.tap(find.text('μιλάω'));
      await tester.pump();

      expect(selected, isEmpty);
    });
  });
}
