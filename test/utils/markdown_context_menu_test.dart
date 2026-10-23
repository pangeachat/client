import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/markdown_context_menu.dart';

/// #9381: a Flutter-drawn Paste on iOS 16+ reads the clipboard from app code,
/// so iOS shows its "Allow Paste" prompt and the app hangs (CLIENT-EQ0). Where
/// iOS can show its own menu, the composer must use it, with the markdown
/// actions added to it; elsewhere it keeps the Flutter-drawn menu.
void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await lookupL10n(const Locale('en'));
  });

  Future<TextEditingController> showMenuWithWordSelected(
    WidgetTester tester, {
    required bool systemMenuSupported,
  }) async {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(supportsShowingSystemContextMenu: systemMenuSupported),
          child: child!,
        ),
        home: Scaffold(
          body: TextField(
            controller: controller,
            contextMenuBuilder: (context, editableTextState) =>
                MarkdownContextMenu(
                  editableTextState: editableTextState,
                  controller: controller,
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'iOS shows its own menu, with the markdown actions added to it',
    (tester) async {
      final shownItems = <Map<String, dynamic>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'ContextMenu.showSystemContextMenu') {
          final arguments = call.arguments as Map<String, dynamic>;
          shownItems
            ..clear()
            ..addAll(
              (arguments['items'] as List<dynamic>)
                  .cast<Map<String, dynamic>>(),
            );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final controller = await showMenuWithWordSelected(
        tester,
        systemMenuSupported: true,
      );

      expect(find.byType(SystemContextMenu), findsOneWidget);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      expect(shownItems.map((item) => item['type']), contains('copy'));
      final customItems = shownItems.where((item) => item['type'] == 'custom');
      expect(customItems.map((item) => item['title']), [
        l10n.link,
        l10n.checkList,
        l10n.boldText,
        l10n.italicText,
        l10n.strikeThrough,
      ]);

      final bold = customItems.firstWhere(
        (item) => item['title'] == l10n.boldText,
      );
      await messenger.handlePlatformMessage(
        SystemChannels.platform.name,
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('ContextMenu.onPerformCustomAction', [0, bold['id']]),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();

      expect(controller.text, '**hello** world');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'without the system menu, the Flutter-drawn menu keeps the markdown actions',
    (tester) async {
      final controller = await showMenuWithWordSelected(
        tester,
        systemMenuSupported: false,
      );

      expect(find.byType(SystemContextMenu), findsNothing);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);

      // The markdown actions sit past the toolbar's first page.
      final more = MaterialLocalizations.of(
        tester.element(find.byType(TextField)),
      ).moreButtonTooltip;
      await tester.tap(find.byTooltip(more));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.boldText));
      await tester.pumpAndSettle();

      expect(controller.text, '**hello** world');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
