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

/// #8767 — the structural half of #8689 finding 12: a chat-list row is ONE
/// button with nothing interactive nested inside it. On web the row is a
/// role=button node, and ARIA's presentational-children rule lets assistive
/// tech flatten or skip controls nested in a button. The avatar is
/// decorative (the context menu is the row's long-press), invite rows have
/// no decline button (tapping the row opens the accept/decline dialog), and
/// the archive page's delete button is a semantic sibling of the row.
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
    void Function()? onForget,
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
              onForget: onForget,
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

  testWidgets('the row is one button with no interactive descendants', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = makeRoom(membership: Membership.invite);
    final context = await pumpItem(tester, room, onLongPress: (_) {});
    final l10n = L10n.of(context);

    final row = rowButtonNode(tester);
    final data = row.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(
      data.hasAction(SemanticsAction.longPress),
      isTrue,
      reason: 'the context menu is the row node\'s long-press action',
    );

    for (final control in [l10n.moreOptions, l10n.declineInvitation]) {
      expect(
        nodesNamed(tester, control),
        isEmpty,
        reason:
            '"$control" is gone (#8767): the avatar is decorative and the '
            'decline choice lives in the tap dialog',
      );
    }
    var interactiveInside = false;
    void visit(SemanticsNode node) {
      if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
        interactiveInside = true;
      }
      node.visitChildren((child) {
        visit(child);
        return !interactiveInside;
      });
    }

    row.visitChildren((child) {
      visit(child);
      return !interactiveInside;
    });
    expect(
      interactiveInside,
      isFalse,
      reason:
          'nothing tappable may nest inside the row button — ARIA treats a '
          'button\'s children as presentational (#8767)',
    );
    semantics.dispose();
  });

  testWidgets('the menu is a named custom action with a long-press hint', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var menuOpened = 0;
    final context = await pumpItem(
      tester,
      makeRoom(),
      onLongPress: (_) => menuOpened++,
    );
    final l10n = L10n.of(context);

    final row = rowButtonNode(tester);
    expect(
      row.hintOverrides?.onLongPressHint,
      l10n.showMoreOptionsHint,
      reason: 'TalkBack names what double-tap-and-hold does',
    );
    // The hint override is itself encoded as a custom-action entry, so pick
    // the named one out rather than expecting a single id.
    final actionId = row
        .getSemanticsData()
        .customSemanticsActionIds!
        .singleWhere(
          (id) =>
              CustomSemanticsAction.getAction(id)!.label == l10n.moreOptions,
          orElse: () => fail(
            'iOS ignores hint overrides, so the menu must be a named action '
            'in the VoiceOver rotor',
          ),
        );
    row.owner!.performAction(row.id, SemanticsAction.customAction, actionId);
    await tester.pumpAndSettle();
    expect(menuOpened, 1);
    semantics.dispose();
  });

  testWidgets('semantic long-press on the row opens the menu', (tester) async {
    final semantics = tester.ensureSemantics();
    var menuOpened = 0;
    var rowOpened = 0;
    await pumpItem(
      tester,
      makeRoom(),
      onTap: () => rowOpened++,
      onLongPress: (_) => menuOpened++,
    );

    final row = rowButtonNode(tester);
    row.owner!.performAction(row.id, SemanticsAction.longPress);
    await tester.pumpAndSettle();
    expect(menuOpened, 1);
    expect(rowOpened, 0);
    semantics.dispose();
  });

  testWidgets('pointer: the whole row — avatar included — opens the chat; '
      'long-press opens the menu', (tester) async {
    var menuOpened = 0;
    var rowOpened = 0;
    await pumpItem(
      tester,
      makeRoom(),
      onTap: () => rowOpened++,
      onLongPress: (_) => menuOpened++,
    );

    final rowRect = tester.getRect(find.byType(ChatListItem));
    await tester.tapAt(rowRect.center);
    await tester.pumpAndSettle();
    expect(rowOpened, 1);

    // The avatar is decorative: its taps fall through to the row (#8767).
    await tester.tapAt(
      Offset(rowRect.left + 8 + Avatar.defaultSize / 2, rowRect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(rowOpened, 2);
    expect(menuOpened, 0);

    await tester.longPressAt(rowRect.center);
    await tester.pumpAndSettle();
    expect(menuOpened, 1);
    expect(rowOpened, 2);
  });

  testWidgets('an archive row exposes exactly one delete control, beside '
      'the row', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = makeRoom(membership: Membership.leave);
    final context = await pumpItem(tester, room, onForget: () {});
    final l10n = L10n.of(context);

    // The layout spacer copy must contribute neither a semantics node nor a
    // second focusable button.
    expect(nodesNamed(tester, l10n.delete), hasLength(1));
    final row = rowButtonNode(tester);
    var inRow = false;
    row.visitChildren((child) {
      inRow = inRow || subtreePresents(child, l10n.delete);
      return !inRow;
    });
    expect(
      inRow,
      isFalse,
      reason: 'the delete button is a sibling of the row button, not inside',
    );
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
