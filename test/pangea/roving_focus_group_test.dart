import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/navi_rail_item.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #8877 — a list of like controls is ONE Tab stop, with the arrow keys moving
/// focus inside it (accessibility.instructions.md → One Tab stop per list).
/// Covers the shared [RovingFocusGroup] with plain items, then the two real
/// lists' items wired through `rovingId`: the nav rail's [NaviRailItem] and
/// the chat list's [ChatListItem].
class _Item extends StatelessWidget {
  final String id;
  final void Function(String id) onTap;

  const _Item(this.id, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      focusNode: RovingFocusGroup.nodeOf(context, id),
      onTap: () => onTap(id),
      child: SizedBox(height: 40, width: 200, child: Text(id)),
    );
  }
}

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  /// Whether the control around [finder]'s widget has primary focus.
  bool focused(WidgetTester tester, Finder finder) =>
      Focus.of(tester.element(finder.first)).hasPrimaryFocus;

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  /// A group between two ordinary buttons, so the tests can see focus enter
  /// and leave it. [list] defaults to a plain column of [_Item]s.
  Widget harness({
    required List<String> ids,
    String? selectedId,
    void Function(String id)? onTap,
    Widget? list,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextButton(onPressed: () {}, child: const Text('before')),
            RovingFocusGroup(
              ids: ids,
              selectedId: selectedId,
              child:
                  list ??
                  Column(
                    children: [
                      for (final id in ids) _Item(id, onTap: onTap ?? (_) {}),
                    ],
                  ),
            ),
            TextButton(onPressed: () {}, child: const Text('after')),
          ],
        ),
      ),
    );
  }

  testWidgets('Tab lands on the selected item once, leaves in one press, and '
      'Shift+Tab comes back to it', (tester) async {
    await tester.pumpWidget(harness(ids: ['a', 'b', 'c'], selectedId: 'b'));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.tab);
    expect(focused(tester, find.text('before')), isTrue);
    await press(tester, LogicalKeyboardKey.tab);
    expect(
      focused(tester, find.text('b')),
      isTrue,
      reason: 'Tab enters the list at the selected item',
    );
    await press(tester, LogicalKeyboardKey.tab);
    expect(
      focused(tester, find.text('after')),
      isTrue,
      reason: 'one stop for the whole list, not one per item',
    );
    await press(tester, LogicalKeyboardKey.tab, shift: true);
    expect(focused(tester, find.text('b')), isTrue);
    await press(tester, LogicalKeyboardKey.tab, shift: true);
    expect(focused(tester, find.text('before')), isTrue);
  });

  testWidgets(
    'Up/Down move one item at a time and clamp at the ends, Enter activates, '
    'and Tab returns to the last item focused',
    (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        harness(ids: ['a', 'b', 'c'], selectedId: 'b', onTap: tapped.add),
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, find.text('b')), isTrue);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, find.text('c')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, find.text('c')), isTrue, reason: 'no wrap');
      await press(tester, LogicalKeyboardKey.enter);
      expect(tapped, ['c']);

      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(tester, find.text('a')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(tester, find.text('a')), isTrue, reason: 'no wrap');

      await press(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, find.text('after')), isTrue);
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(
        focused(tester, find.text('a')),
        isTrue,
        reason: 'Tab returns to the item last focused, not to the selection',
      );
    },
  );

  testWidgets('a new selection is where Tab lands next', (tester) async {
    await tester.pumpWidget(harness(ids: ['a', 'b', 'c'], selectedId: 'a'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.tab);
    expect(focused(tester, find.text('a')), isTrue);
    await press(tester, LogicalKeyboardKey.tab);

    await tester.pumpWidget(harness(ids: ['a', 'b', 'c'], selectedId: 'c'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.tab, shift: true);
    expect(focused(tester, find.text('c')), isTrue);
  });

  testWidgets(
    'a selected item scrolled out of a lazy list does not cost the list '
    'its Tab stop',
    (tester) async {
      final ids = [for (var i = 0; i < 200; i++) 'row $i'];
      await tester.pumpWidget(
        harness(
          ids: ids,
          selectedId: 'row 150',
          list: SizedBox(
            height: 200,
            child: ListView.builder(
              itemCount: ids.length,
              itemExtent: 40,
              itemBuilder: (context, i) => _Item(ids[i], onTap: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('row 150'),
        findsNothing,
        reason: 'fixture: the selected row is not built',
      );

      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(
        focused(tester, find.text('row 0')),
        isTrue,
        reason:
            'Tab falls back to the first built row instead of skipping '
            'the list',
      );
      await press(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, find.text('after')), isTrue);
    },
  );

  testWidgets(
    'Down at the edge of the built rows scrolls so the next press reaches '
    'the next row',
    (tester) async {
      final ids = [for (var i = 0; i < 200; i++) 'row $i'];
      await tester.pumpWidget(
        harness(
          ids: ids,
          list: SizedBox(
            height: 200,
            child: ListView.builder(
              // Build only what is visible, so the row below the viewport
              // does not exist yet.
              cacheExtent: 0,
              itemCount: ids.length,
              itemExtent: 40,
              itemBuilder: (context, i) => _Item(ids[i], onTap: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focused(tester, find.text('row 4')), isTrue);
      expect(find.text('row 5'), findsNothing, reason: 'fixture: not built');

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(find.text('row 5'), findsOneWidget, reason: 'the list scrolled');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(tester, find.text('row 5')), isTrue);
    },
  );

  group('the real items wire through rovingId', () {
    late Client client;

    setUpAll(() async {
      dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
      MatrixState.pangeaController = FakePangeaController();
      client = await getTestClient();
    });

    tearDownAll(() async {
      await client.dispose();
    });

    Room makeRoom(String id, String name) {
      final room = Room(id: id, client: client, membership: Membership.join);
      room.setState(
        Event(
          type: EventTypes.RoomName,
          content: {'name': name},
          stateKey: '',
          senderId: '@alice:example.org',
          eventId: '\$name-$id',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
      return room;
    }

    testWidgets('NaviRailItem: one stop, arrows rove, Enter activates', (
      tester,
    ) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Provider<MatrixState>.value(
              value: _FakeMatrixState(client),
              child: Column(
                children: [
                  TextButton(onPressed: () {}, child: const Text('before')),
                  RovingFocusGroup(
                    ids: const ['world', 'chats'],
                    selectedId: 'chats',
                    child: Column(
                      children: [
                        NaviRailItem(
                          toolTip: 'World',
                          isSelected: false,
                          onTap: () => tapped.add('world'),
                          icon: const Icon(Icons.public),
                          naviRailWidth: 80,
                          rovingId: 'world',
                        ),
                        NaviRailItem(
                          toolTip: 'Chats',
                          isSelected: true,
                          onTap: () => tapped.add('chats'),
                          icon: const Icon(Icons.forum),
                          naviRailWidth: 80,
                          rovingId: 'chats',
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () {}, child: const Text('after')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, find.byIcon(Icons.forum)), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(tester, find.byIcon(Icons.public)), isTrue);
      await press(tester, LogicalKeyboardKey.enter);
      expect(tapped, ['world']);
      await press(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, find.text('after')), isTrue);
    });

    testWidgets('ChatListItem rows: one stop, arrows rove, Enter opens', (
      tester,
    ) async {
      final rooms = [
        makeRoom('!alpha:example.org', 'Alpha chat'),
        makeRoom('!beta:example.org', 'Beta chat'),
      ];
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                TextButton(onPressed: () {}, child: const Text('before')),
                RovingFocusGroup(
                  ids: [for (final room in rooms) room.id],
                  selectedId: rooms[1].id,
                  child: SizedBox(
                    width: 380,
                    child: Column(
                      children: [
                        for (final room in rooms)
                          ChatListItem(
                            room,
                            onTap: () => opened.add(room.id),
                            rovingId: room.id,
                          ),
                      ],
                    ),
                  ),
                ),
                TextButton(onPressed: () {}, child: const Text('after')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, find.text('Beta chat')), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(tester, find.text('Alpha chat')), isTrue);
      await press(tester, LogicalKeyboardKey.enter);
      expect(opened, ['!alpha:example.org']);
      await press(tester, LogicalKeyboardKey.tab);
      expect(focused(tester, find.text('after')), isTrue);
    });
  });
}
