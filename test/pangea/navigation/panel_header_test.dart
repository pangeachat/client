import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/panel_header.dart';

/// The shared panel header's geometry. A header with no leading control — the
/// wide course card, whose chevron trails beside its actions (#8866) — starts
/// its title at the same inset the trailing glyphs end at, so text and
/// buttons share one edge; the course's collapsed progress bar insets to the
/// same number, which is what stops it running past the buttons.
void main() {
  Future<void> pumpWide(WidgetTester tester, PanelHeader header) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 400, child: header),
          ),
        ),
      ),
    );
  }

  testWidgets('with no leading control, title and trailing glyphs share the '
      'content inset', (tester) async {
    await pumpWide(
      tester,
      PanelHeader(
        leading: null,
        title: 'Course',
        trailing: IconButton(
          icon: const Icon(Icons.my_location),
          onPressed: () {},
        ),
      ),
    );

    final header = tester.getRect(find.byType(PanelHeader));
    expect(
      tester.getRect(find.text('Course')).left,
      header.left + PanelHeader.contentInset,
    );
    expect(
      tester.getRect(find.byIcon(Icons.my_location)).right,
      header.right - PanelHeader.contentInset,
    );
    // The height the context bar states for itself.
    expect(header.height, PanelHeader.wideHeight);
  });

  testWidgets('with a leading control, the title follows it', (tester) async {
    await pumpWide(
      tester,
      PanelHeader(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () {}),
        title: 'Chats',
      ),
    );

    final header = tester.getRect(find.byType(PanelHeader));
    final close = tester.getRect(find.byType(IconButton));
    expect(close.left, header.left + PanelHeader.horizontalPadding);
    expect(tester.getRect(find.text('Chats')).left, close.right + 8.0);
  });
}
