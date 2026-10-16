import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/widgets/bold_tonal_button.dart';
import 'audio_players_stub.dart';

/// The course page's bold secondary button (#9420): one accessible node that
/// names it and that a screen reader can press, whether or not it shows a
/// label.
void main() {
  setUpAll(AudioPlayersStub.install);
  tearDownAll(AudioPlayersStub.uninstall);

  Future<void> pump(WidgetTester tester, BoldTonalButton button) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: button)),
      ),
    );
  }

  void press(WidgetTester tester, String label) =>
      tester.semantics.tap(find.semantics.byLabel(label));

  testWidgets('a pointer tap and a screen-reader tap both press it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      BoldTonalButton(
        icon: Icons.add,
        label: 'Practice',
        semanticsLabel: 'Practice, 3 words',
        onPressed: () => taps++,
      ),
    );
    expect(find.text('Practice'), findsOneWidget);

    await tester.tap(find.byType(BoldTonalButton));
    await tester.pumpAndSettle();
    press(tester, 'Practice, 3 words');
    expect(taps, 2);
    semantics.dispose();
  });

  testWidgets('icon-only, it keeps its name as its label and tooltip', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      BoldTonalButton(
        icon: Icons.person_add_outlined,
        semanticsLabel: 'Invite',
        onPressed: () {},
      ),
    );
    expect(find.byTooltip('Invite'), findsOneWidget);
    expect(find.bySemanticsLabel('Invite'), findsOneWidget);
    expect(
      tester.getSize(find.byType(BoldTonalButton)).width,
      greaterThanOrEqualTo(38.0),
    );
    semantics.dispose();
  });

  testWidgets('without onPressed it offers no tap', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const BoldTonalButton(label: 'See all', onPressed: null),
    );
    final data = tester
        .getSemantics(find.bySemanticsLabel('See all'))
        .getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });
}
