import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/toolbar/word_card/lemma_reaction_picker.dart';

/// #7931 — a word with 5+ emoji associations overflowed the word card, and the
/// extra emojis were unreachable. The row scrolls horizontally instead, while
/// still centering the emojis when they all fit.
void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required int emojiCount,
    required double width,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ScrollableEmojiRow(
                children: List.generate(
                  emojiCount,
                  (i) => SizedBox(
                    height: 55.0,
                    width: 55.0,
                    child: Center(child: Text('e$i')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('does not overflow when the emojis exceed the available width', (
    tester,
  ) async {
    await pumpRow(tester, emojiCount: 8, width: 200.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolls to reveal emojis that do not fit', (tester) async {
    await pumpRow(tester, emojiCount: 8, width: 200.0);

    final lastEmoji = find.text('e7');
    expect(lastEmoji, findsOneWidget);

    final beforeScroll = tester.getTopLeft(lastEmoji).dx;
    await tester.drag(
      find.byType(ScrollableEmojiRow),
      const Offset(-200.0, 0.0),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(lastEmoji).dx, lessThan(beforeScroll));
  });

  testWidgets('centers the emojis when they all fit', (tester) async {
    const width = 400.0;
    await pumpRow(tester, emojiCount: 3, width: width);

    final rowCenter = tester.getCenter(find.byType(ScrollableEmojiRow)).dx;
    final emojisCenter =
        (tester.getTopLeft(find.text('e0')).dx +
            tester.getBottomRight(find.text('e2')).dx) /
        2;

    expect(emojisCenter, moreOrLessEquals(rowCenter, epsilon: 1.0));
  });
}
