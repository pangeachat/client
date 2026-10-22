import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/chat_list_search.dart';
import 'package:fluffychat/routes/chat_list/pangea_chat_list_header.dart';

/// #9449: closing the chat list's search from the chats header's search icon
/// ends the search, as the field's own close control already did. Before, the
/// field disappeared but the list stayed filtered by text nobody could see.
void main() {
  const headerToggle = ValueKey('header-search-toggle');

  Future<_ChatListSearchHostState> pumpHost(
    WidgetTester tester,
    ValueNotifier<bool> toggle,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: _ChatListSearchHost(toggle: toggle)),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state(find.byType(_ChatListSearchHost));
  }

  Future<void> openAndSearch(WidgetTester tester, String query) async {
    await tester.tap(find.byKey(headerToggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  testWidgets('closing search from the header icon ends the search', (
    tester,
  ) async {
    final toggle = ValueNotifier(false);
    addTearDown(toggle.dispose);
    final search = await pumpHost(tester, toggle);

    await openAndSearch(tester, 'ana');
    expect(search.isSearchMode, isTrue);

    await tester.tap(find.byKey(headerToggle));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(search.isSearchMode, isFalse);
    expect(search.searchController.text, isEmpty);

    // Opening it again starts from an empty field.
    await tester.tap(find.byKey(headerToggle));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(search.isSearchMode, isFalse);
  });

  testWidgets('the field\'s own close control ends the search', (tester) async {
    final toggle = ValueNotifier(false);
    addTearDown(toggle.dispose);
    final search = await pumpHost(tester, toggle);

    await openAndSearch(tester, 'ana');
    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pumpAndSettle();

    expect(toggle.value, isFalse);
    expect(find.byType(TextField), findsNothing);
    expect(search.isSearchMode, isFalse);
    expect(search.searchController.text, isEmpty);
  });
}

/// Hosts [ChatListSearch] the way the chats panel does: the header's search
/// icon flips [toggle] from outside the list (LeftPanelChatListSubpage), and
/// the field row shows while it is on (ChatListBody).
class _ChatListSearchHost extends StatefulWidget {
  final ValueNotifier<bool> toggle;

  const _ChatListSearchHost({required this.toggle});

  @override
  State<_ChatListSearchHost> createState() => _ChatListSearchHostState();
}

class _ChatListSearchHostState extends State<_ChatListSearchHost>
    with ChatListSearch<_ChatListSearchHost> {
  @override
  ValueListenable<bool> get searchFieldVisibility => widget.toggle;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      IconButton(
        key: const ValueKey('header-search-toggle'),
        icon: const Icon(Icons.search_outlined),
        onPressed: () => widget.toggle.value = !widget.toggle.value,
      ),
      ValueListenableBuilder<bool>(
        valueListenable: widget.toggle,
        builder: (context, visible, _) => visible
            ? PangeaChatListSearchField(
                controller: this,
                autofocus: true,
                onClose: () => widget.toggle.value = false,
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}
