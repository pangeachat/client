import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #8767 — the structural half of #8689 finding 12: a chat-list row's live
/// controls (the "More options" avatar, the decline/delete icon button) are
/// semantic SIBLINGS of the row's open-chat button, never its descendants.
/// On web the row is a role=button node, and ARIA's presentational-children
/// rule lets assistive tech flatten or skip controls nested in a button.
void main() {
  late Client client;

  const roomId = '!chat:fakeServer.notExisting';
  const roomName = 'Library registration roleplay';
  const senderId = '@alice:example.org';

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room makeRoom({Membership membership = Membership.join}) {
    final room = Room(id: roomId, client: client, membership: membership);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': roomName},
        stateKey: '',
        senderId: senderId,
        eventId: '\$name',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    room.setState(
      Event(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': 'Alice'},
        stateKey: senderId,
        senderId: senderId,
        eventId: '\$member',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    return room;
  }

  Future<BuildContext> pumpItem(
    WidgetTester tester,
    Room room, {
    void Function()? onTap,
    void Function(BuildContext)? onLongPress,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: ChatListItem(
              room,
              onTap: onTap ?? () {},
              onLongPress: onLongPress,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.element(find.byType(ChatListItem));
  }

  /// Whether a node presents [name] to assistive tech — icon buttons carry
  /// their name in the semantics `tooltip` field, labeled nodes in `label`.
  bool presentsName(SemanticsNode node, String name) {
    final data = node.getSemanticsData();
    return data.label == name || data.tooltip == name;
  }

  /// Whether [node] or any of its descendants presents [name].
  bool subtreePresents(SemanticsNode node, String name) {
    if (presentsName(node, name)) return true;
    var found = false;
    node.visitChildren((child) {
      found = found || subtreePresents(child, name);
      return !found;
    });
    return found;
  }

  /// The row's open-chat node: the one with a tap action whose label starts
  /// with the room name.
  SemanticsNode rowButtonNode(WidgetTester tester) =>
      tester.getSemantics(find.bySemanticsLabel(RegExp('^$roomName')));

  /// Every node in the tree presenting [name], walked from the semantics
  /// root that owns the row.
  List<SemanticsNode> nodesNamed(WidgetTester tester, String name) {
    final owner = rowButtonNode(tester).owner!;
    final result = <SemanticsNode>[];
    void visit(SemanticsNode node) {
      if (presentsName(node, name)) result.add(node);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(owner.rootSemanticsNode!);
    return result;
  }

  testWidgets('the row button contains no interactive descendants', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = makeRoom(membership: Membership.invite);
    final context = await pumpItem(tester, room, onLongPress: (_) {});
    final l10n = L10n.of(context);

    final row = rowButtonNode(tester);
    expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    for (final control in [l10n.moreOptions, l10n.declineInvitation]) {
      expect(
        nodesNamed(tester, control),
        hasLength(1),
        reason: '"$control" must be reachable as its own node',
      );
      var inRow = false;
      row.visitChildren((child) {
        inRow = inRow || subtreePresents(child, control);
        return !inRow;
      });
      expect(
        inRow,
        isFalse,
        reason:
            '"$control" may not be a descendant of the row button — ARIA '
            'treats a button\'s children as presentational (#8767)',
      );
    }
    semantics.dispose();
  });

  testWidgets('semantic activation of More options opens the row menu', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var menuOpened = 0;
    var rowOpened = 0;
    final context = await pumpItem(
      tester,
      makeRoom(),
      onTap: () => rowOpened++,
      onLongPress: (_) => menuOpened++,
    );
    final l10n = L10n.of(context);

    final node = nodesNamed(tester, l10n.moreOptions).single;
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(menuOpened, 1);
    expect(rowOpened, 0);
    semantics.dispose();
  });

  testWidgets('pointer parity: row opens the chat, avatar opens the menu', (
    tester,
  ) async {
    var menuOpened = 0;
    var rowOpened = 0;
    await pumpItem(
      tester,
      makeRoom(),
      onTap: () => rowOpened++,
      onLongPress: (_) => menuOpened++,
    );

    final rowRect = tester.getRect(find.byType(ChatListItem));
    // Center of the row — clear of the avatar and any trailing control.
    await tester.tapAt(rowRect.center);
    await tester.pumpAndSettle();
    expect(rowOpened, 1);
    expect(menuOpened, 0);

    // Center of the leading avatar slot (contentPadding 8 + half the slot).
    await tester.tapAt(
      Offset(rowRect.left + 8 + Avatar.defaultSize / 2, rowRect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(menuOpened, 1);
    expect(rowOpened, 1);

    // Long-press on the row body still opens the menu via the tile. (On the
    // avatar itself the Tooltip's deeper long-press recognizer wins the
    // arena and shows the tooltip — the same outcome as before #8767.)
    await tester.longPressAt(rowRect.center);
    await tester.pumpAndSettle();
    expect(menuOpened, 2);
    expect(rowOpened, 1);
  });

  testWidgets('an invite row exposes exactly one live decline control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = makeRoom(membership: Membership.invite);
    final context = await pumpItem(tester, room);
    final l10n = L10n.of(context);

    // The layout spacer copy must contribute neither a semantics node nor a
    // second focusable button.
    expect(nodesNamed(tester, l10n.declineInvitation), hasLength(1));
    final focusableIconButtons = tester
        .binding
        .focusManager
        .rootScope
        .traversalDescendants
        .where(
          (node) =>
              node.context?.findAncestorWidgetOfExactType<IconButton>() != null,
        );
    expect(
      focusableIconButtons.length,
      1,
      reason: 'exactly one keyboard-reachable decline button',
    );
    semantics.dispose();
  });
}
