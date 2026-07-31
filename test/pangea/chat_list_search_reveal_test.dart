import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat_list/chat_list_search_reveal.dart';

/// #7941 — a learner with many chats scrolls the list looking for one, gives
/// up and taps the search icon. The field mounts as the first sliver, above
/// the viewport, so pre-fix the list just shifted and the search bar they
/// asked for stayed out of sight. Opening search must bring the top back.
void main() {
  late ScrollController scrollController;

  setUp(() => scrollController = ScrollController());
  tearDown(() => scrollController.dispose());

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ListView.builder(
              controller: scrollController,
              itemCount: 60,
              itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$i')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('scrolled-down list rides back to the top', (tester) async {
    await pumpList(tester);

    scrollController.jumpTo(1200);
    await tester.pump();
    expect(scrollController.position.pixels, 1200);

    revealChatListSearchField(scrollController);
    await tester.pumpAndSettle();

    expect(scrollController.position.pixels, 0);
  });

  testWidgets('animates rather than jumping, so the move is legible', (
    tester,
  ) async {
    await pumpList(tester);

    scrollController.jumpTo(1200);
    await tester.pump();

    revealChatListSearchField(scrollController);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));

    // Mid-flight: moving toward the top, but not there yet.
    expect(scrollController.position.pixels, lessThan(1200));
    expect(scrollController.position.pixels, greaterThan(0));

    await tester.pumpAndSettle();
    expect(scrollController.position.pixels, 0);
  });

  testWidgets('already at the top is a no-op', (tester) async {
    await pumpList(tester);

    revealChatListSearchField(scrollController);
    await tester.pump();

    expect(scrollController.position.pixels, 0);
  });

  test('no clients attached is a no-op, not a crash', () {
    // The toggle can flip before the list has been laid out.
    expect(scrollController.hasClients, isFalse);
    expect(() => revealChatListSearchField(scrollController), returnsNormally);
  });
}
