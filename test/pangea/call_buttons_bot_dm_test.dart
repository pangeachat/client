import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/chat_call_buttons.dart';
import 'package:fluffychat/routes/chat/calls/rtc_focus.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// The call buttons were gated on `isDirectChat` alone, and a bot DM IS a
/// direct chat -- so the Pangea Bot room offered Call and Video call. The bot
/// has no VoIP, so tapping one rang nobody and left the caller waiting out the
/// no-answer timeout.
///
/// Asserted over what RENDERS, not over the predicate alone. A test that only
/// calls the predicate leaves the site free to stop asking it: the gate could
/// be reverted to `isDirectChat` at the app bar with every test still green.
/// The gate therefore lives inside [ChatCallButtons], which mounts on its own,
/// and these pump it.
///
/// Both halves of `isBotDM` are exercised, because they catch different rooms:
/// `m.direct` names the bot as the other party, and `bot_options.mode` marks a
/// room the account data alone does not report as a bot DM.
///
/// The enabled/disabled half is asserted over a TRANSITION, not just the first
/// frame. A first-frame test cannot tell a widget that recomputes from one that
/// happened to render the right answer once: the buttons gate on how many the
/// server counts as joined, and the bug was that they never re-read it. So
/// these mount the widget, then deliver a real sync that raises or lowers the
/// room's joined count -- an invitee accepts, a member leaves -- and assert the
/// buttons flip in response, which is what proves they track the count live
/// rather than freezing on the first read.

/// Skips `initMatrix()` -- push, notification listeners and the Pangea
/// controller are all irrelevant here and none of them stand up under
/// `flutter test`. The buttons only want `Matrix.of(context).callService`,
/// which is served with a stubbed focus lookup so the network is never asked.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}

  @override
  CallService callServiceFor(String clientName) =>
      (widget as _TestMatrix).callService;
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
    required this.callService,
  });

  final CallService callService;

  @override
  MatrixState createState() => _TestMatrixState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const botId = '@pangeabot:fakeServer.notExisting';
  const friendId = '@friend:fakeServer.notExisting';
  const roomId = '!calls:fakeServer.notExisting';
  final homeserver = Uri.parse('https://fakeServer.notExisting');

  late Client client;
  late SharedPreferences store;
  CallService? callService;

  setUpAll(() async {
    // isBotDM reads BotName.byEnvironment, which needs GetStorage and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('call_buttons_bot');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': botId,
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
    client.homeserver = homeserver;
  });

  tearDown(() async {
    await callService?.dispose();
    callService = null;
    await client.dispose();
  });

  /// A `m.room.member` state event -- the unit a join or a leave arrives as.
  /// Used to seed how many member states the client has LOADED into memory,
  /// which is a different thing from the server's joined count in the summary:
  /// the lazy-loading fixture below deliberately loads fewer member states than
  /// the summary counts, to prove the buttons read the authoritative count and
  /// not the in-memory member list.
  Event memberEvent(Room room, String userId, String membership) => Event(
    type: EventTypes.RoomMember,
    content: {'membership': membership},
    stateKey: userId,
    senderId: userId,
    eventId: '\$member_${userId}_$membership',
    originServerTs: DateTime.now(),
    room: room,
  );

  /// Builds a DM-shaped room and REGISTERS it on the client, so a later
  /// [syncJoinedCount] updates this very instance rather than a fresh copy.
  ///
  /// [summaryCount] is the server's authoritative joined count (what the
  /// buttons gate on); [loadedMembers] is how many `m.room.member` join states
  /// are actually in memory. They default to the same, an ordinary synced room;
  /// the lazy-loading test sets [summaryCount] higher than [loadedMembers] to
  /// stand up an established DM whose peer member event has not been loaded.
  Room buildRoom({
    String? directChatWith,
    String? botMode,
    int loadedMembers = 2,
    int? summaryCount,
  }) {
    final room = Room(
      id: roomId,
      client: client,
      membership: Membership.join,
      summary: RoomSummary.fromJson({
        'm.joined_member_count': summaryCount ?? loadedMembers,
        'm.invited_member_count': 0,
        'm.heroes': <String>[],
      }),
    );
    // Registered so `client.handleSync` finds and mutates THIS instance (it
    // matches by room id), which is the instance the pumped widget holds.
    client.rooms.add(room);
    // The member states the client has loaded. Not what the buttons count --
    // they read the summary -- but seeded so the lazy-loading fixture can load
    // fewer than the summary reports.
    final joined = [client.userID!, friendId, '@third:fakeServer.notExisting'];
    for (var i = 0; i < loadedMembers; i++) {
      room.setState(memberEvent(room, joined[i], 'join'));
    }
    if (botMode != null) {
      room.setState(
        Event(
          type: PangeaEventTypes.botOptions,
          content: {'mode': botMode},
          stateKey: '',
          senderId: botId,
          eventId: '\$botOptions',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
    }
    if (directChatWith != null) {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          directChatWith: [roomId],
        },
      );
    }
    return room;
  }

  /// Delivers a real sync that sets the room's joined count to [count]. This is
  /// the exact path a live join or leave takes: the SDK merges the summary and
  /// then fires `client.onSync`, the stream the buttons recompute on. Driving
  /// the transition tests through it -- rather than poking the summary by hand
  /// -- means they exercise the same code a running client does.
  ///
  /// Run through `tester.runAsync`: `handleSync` does real asynchronous work
  /// (the store write behind the merge), which deadlocks in the fake-async zone
  /// a `testWidgets` body runs in -- it must run on the real clock. This is the
  /// same wrapping the SDK-sync tests in this repo use.
  Future<void> syncJoinedCount(WidgetTester tester, Room room, int count) =>
      tester.runAsync(
        () => client.handleSync(
          SyncUpdate(
            nextBatch: 'batch_$count',
            rooms: RoomsUpdate(
              join: {
                room.id: JoinedRoomUpdate(
                  summary: RoomSummary.fromJson({
                    'm.joined_member_count': count,
                    'm.invited_member_count': 0,
                    'm.heroes': <String>[],
                  }),
                ),
              },
            ),
          ),
        ),
      );

  /// Delivers a real sync in which THIS account leaves [room]. A leave arrives
  /// under `rooms.leave`, which carries no summary: the SDK archives the room
  /// and sets its membership to `leave` but does not lower the stale joined
  /// count. Same `runAsync` wrapping and `onSync` fire as [syncJoinedCount].
  Future<void> syncLeave(WidgetTester tester, Room room) => tester.runAsync(
    () => client.handleSync(
      SyncUpdate(
        nextBatch: 'left',
        rooms: RoomsUpdate(leave: {room.id: LeftRoomUpdate()}),
      ),
    ),
  );

  /// Serves `.well-known` and nothing else, so the focus half of the gate is a
  /// real answer rather than a stub of the widget's own decision.
  http.Client wellKnown({required bool advertisesFocus}) =>
      MockClient((request) async {
        if (request.url.path != '/.well-known/matrix/client') {
          return http.Response('{"errcode":"M_NOT_FOUND"}', 404);
        }
        return http.Response(
          jsonEncode({
            'm.homeserver': {'base_url': homeserver.toString()},
            if (advertisesFocus)
              'org.matrix.msc4143.rtc_foci': [
                {'type': 'livekit', 'livekit_service_url': 'http://sfu:7980'},
              ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

  /// Mounts the buttons where the chat header mounts them -- in an AppBar's
  /// actions -- so the widget is asked for exactly what the app asks it for.
  Future<void> pumpButtons(
    WidgetTester tester,
    Room room, {
    bool advertisesFocus = true,
  }) async {
    final service = callService = CallService(
      client,
      focusDiscovery: RtcFocusDiscovery(
        httpClient: wellKnown(advertisesFocus: advertisesFocus),
      ),
    );
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        callService: service,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(appBar: AppBar(actions: [ChatCallButtons(room)])),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final callButton = find.byIcon(Icons.call_outlined);
  final videoButton = find.byIcon(Icons.videocam_outlined);
  // The IconButtons themselves, so a test can read `onPressed` to tell an
  // enabled button from a greyed one -- the icon alone renders either way.
  final voiceIconButton = find.widgetWithIcon(IconButton, Icons.call_outlined);
  final videoIconButton = find.widgetWithIcon(
    IconButton,
    Icons.videocam_outlined,
  );

  testWidgets('a DM with another person is offered calls', (tester) async {
    final room = buildRoom(directChatWith: friendId);
    expect(
      room.isDirectChat,
      isTrue,
      reason: 'the control must reach the gate',
    );

    await pumpButtons(tester, room);

    expect(callButton, findsOneWidget);
    expect(videoButton, findsOneWidget);
    // Both people are in the DM, so the call can connect: the buttons are live.
    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNotNull,
      reason: 'a two-person DM can place a call',
    );
    expect(tester.widget<IconButton>(videoIconButton).onPressed, isNotNull);
  });

  testWidgets('a DM whose invitee has not joined greys the buttons out', (
    tester,
  ) async {
    // The bug: a fresh DM, the invitee has not accepted, so the server counts
    // only the caller as joined. A call would ring nobody. The buttons must be
    // present but inert, so the caller sees they cannot call yet rather than
    // sitting through a silent no-answer timeout (#8777).
    final room = buildRoom(directChatWith: friendId, loadedMembers: 1);
    expect(
      room.isDirectChat,
      isTrue,
      reason: 'the control must reach the gate',
    );

    await pumpButtons(tester, room);

    // Rendered -- greyed, not hidden -- so the disabled state is the signal.
    expect(callButton, findsOneWidget);
    expect(videoButton, findsOneWidget);
    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNull,
      reason: 'no one else has joined, so the call button is inert',
    );
    expect(
      tester.widget<IconButton>(videoIconButton).onPressed,
      isNull,
      reason: 'no one else has joined, so the video button is inert',
    );
  });

  testWidgets('the buttons enable the moment the invitee joins', (
    tester,
  ) async {
    // The core of #8777's follow-up: a fresh DM renders greyed because the
    // server counts only the caller as joined. The invitee then accepts WHILE
    // the widget is mounted, and the buttons must flip to enabled off that sync
    // alone -- no navigation, no unrelated rebuild.
    final room = buildRoom(directChatWith: friendId, loadedMembers: 1);

    await pumpButtons(tester, room);

    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNull,
      reason: 'only the caller is joined, so the call would ring nobody',
    );

    // The invitee accepts: the next sync raises the joined count to two and
    // fires `client.onSync` -- the stream the buttons recompute on.
    await syncJoinedCount(tester, room, 2);
    await tester.pumpAndSettle();

    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNotNull,
      reason: 'the second member joined, so the call can connect now',
    );
    expect(
      tester.widget<IconButton>(videoIconButton).onPressed,
      isNotNull,
      reason: 'the video button re-enables on the same change',
    );
  });

  testWidgets('the buttons disable the moment the other member leaves', (
    tester,
  ) async {
    // The mirror case: a two-joined DM is callable, the other user leaves, and
    // the next sync drops the joined count to one. Read live off the summary,
    // the buttons must go inert rather than keep an `onPressed` that would start
    // a call ringing nobody.
    final room = buildRoom(directChatWith: friendId);

    await pumpButtons(tester, room);

    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNotNull,
      reason: 'both are joined to start, so a call can connect',
    );

    await syncJoinedCount(tester, room, 1);
    await tester.pumpAndSettle();

    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNull,
      reason: 'the other member left, so the call would ring nobody',
    );
    expect(
      tester.widget<IconButton>(videoIconButton).onPressed,
      isNull,
      reason: 'the video button greys on the same change',
    );
  });

  testWidgets('the buttons disable when THIS account leaves the room', (
    tester,
  ) async {
    // The joined count in the summary INCLUDES this account, so "two joined"
    // does not by itself mean a call can connect. If the account itself leaves,
    // the room is archived with membership `leave`, but the leave sync carries
    // no summary so the stale count is not lowered. Reading the count alone
    // would keep the buttons live for a room the account is no longer in; they
    // must go inert.
    final room = buildRoom(directChatWith: friendId);

    await pumpButtons(tester, room);

    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNotNull,
      reason: 'both are joined to start, so a call can connect',
    );

    await syncLeave(tester, room);
    await tester.pumpAndSettle();

    expect(
      room.membership,
      Membership.leave,
      reason: 'the leave must actually have taken on the room instance',
    );
    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNull,
      reason: 'the account has left; there is no call to place from here',
    );
    expect(tester.widget<IconButton>(videoIconButton).onPressed, isNull);
  });

  testWidgets('the buttons re-read a room object swapped in for the same id', (
    tester,
  ) async {
    // A parent can hand the same widget position a DIFFERENT Room object for the
    // same id -- a rejoin, or the room reloaded from the store -- carrying its
    // own summary. The buttons must reflect the new object's count, not stay on
    // the previous object's until the next sync moves the cached answer.
    final stale = buildRoom(directChatWith: friendId, loadedMembers: 1);

    await pumpButtons(tester, stale);

    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNull,
      reason: 'the first object has only the caller joined',
    );

    // Same id and client, a fresh object, two joined. The guard compared only
    // id and client and would skip the recompute; the buttons must re-read it.
    final fresh = Room(
      id: roomId,
      client: client,
      membership: Membership.join,
      summary: RoomSummary.fromJson({
        'm.joined_member_count': 2,
        'm.invited_member_count': 0,
        'm.heroes': <String>[],
      }),
    );
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        callService: callService!,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(appBar: AppBar(actions: [ChatCallButtons(fresh)])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNotNull,
      reason:
          'the swapped-in object has two joined; the buttons must re-read it',
    );
    expect(tester.widget<IconButton>(videoIconButton).onPressed, isNotNull);
  });

  testWidgets('the buttons drop when a sync reclassifies the room as a bot DM', (
    tester,
  ) async {
    // What the buttons show turns on more than the joined count: whether calls
    // are OFFERED here at all. A sync can flip that -- the room gains
    // `bot_options` and is now a bot DM, which has no VoIP -- while the joined
    // count does not move. The buttons must drop, not stay live off an
    // unchanged count. This is why the widget rebuilds on every sync rather than
    // caching one answer and guarding the rebuild on it.
    final room = buildRoom(directChatWith: friendId);

    await pumpButtons(tester, room);

    expect(callButton, findsOneWidget, reason: 'a plain DM offers the buttons');
    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNotNull,
      reason: 'two are joined, so the call could connect',
    );

    // The room gains its `bot_options`, marking it a bot DM; the joined count is
    // untouched, only the classification changes. The state lands, and then the
    // sync that carried it fires -- the signal the widget rebuilds on.
    room.setState(
      Event(
        type: PangeaEventTypes.botOptions,
        content: {'mode': 'direct_chat'},
        stateKey: '',
        senderId: botId,
        eventId: '\$botify',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    client.onSync.add(SyncUpdate(nextBatch: 'botify'));
    await tester.pumpAndSettle();

    expect(
      callButton,
      findsNothing,
      reason:
          'a bot DM has no VoIP, so the buttons must drop on the reclassify',
    );
    expect(videoButton, findsNothing);
  });

  testWidgets('an established DM stays callable when the peer member state is '
      'not loaded', (tester) async {
    // Lazy loading -- Matrix's default -- can leave an established two-person
    // DM with the peer's `m.room.member` event not in memory, so only one join
    // state is loaded even though the server counts two. Gating on
    // `getParticipants([join]).length` would read one and grey a DM that can
    // plainly place a call; the server's own summary count does not depend on
    // which member events happen to be loaded. This is the case the summary
    // read exists for: summary says two, only one member state is present, the
    // buttons stay live.
    final room = buildRoom(
      directChatWith: friendId,
      loadedMembers: 1,
      summaryCount: 2,
    );
    expect(
      room.getParticipants(const [Membership.join]).length,
      1,
      reason: 'the fixture must actually load fewer members than it counts',
    );
    expect(
      room.summary.mJoinedMemberCount,
      2,
      reason: 'the server still counts both members of the DM',
    );

    await pumpButtons(tester, room);

    expect(
      tester.widget<IconButton>(voiceIconButton).onPressed,
      isNotNull,
      reason:
          'the server counts two joined; an unloaded member must not grey '
          'a callable DM',
    );
    expect(tester.widget<IconButton>(videoIconButton).onPressed, isNotNull);
  });

  testWidgets('the bot DM named by m.direct is not', (tester) async {
    // The case the bug shipped: a real direct chat, so `isDirectChat` alone
    // said yes. Only the bot half can say no here.
    final room = buildRoom(directChatWith: botId);
    expect(room.isDirectChat, isTrue);

    await pumpButtons(tester, room);

    expect(callButton, findsNothing);
    expect(videoButton, findsNothing);
  });

  testWidgets('a bot room its options name, under some other user id, is not', (
    tester,
  ) async {
    // `m.direct` points at a user who is NOT the configured bot, so the name
    // check cannot fire -- `bot_options.mode` is the only thing that knows.
    final room = buildRoom(directChatWith: friendId, botMode: 'direct_chat');
    expect(room.isDirectChat, isTrue);

    await pumpButtons(tester, room);

    expect(callButton, findsNothing);
    expect(videoButton, findsNothing);
  });

  testWidgets('a group room is not offered calls at all', (tester) async {
    await pumpButtons(tester, buildRoom());

    expect(callButton, findsNothing);
    expect(videoButton, findsNothing);
  });

  testWidgets('a homeserver with no focus still offers nothing', (
    tester,
  ) async {
    // The room half of the gate is not the only one. Moving the buttons into
    // their own widget must not have left the focus lookup behind: without an
    // SFU there is nothing for the call to connect to.
    final room = buildRoom(directChatWith: friendId);

    await pumpButtons(tester, room, advertisesFocus: false);

    expect(callButton, findsNothing);
    expect(videoButton, findsNothing);
  });

  // The header's app bar cannot be mounted in a widget test -- `_appBarActions`
  // needs a live ChatController, which needs the whole chat route -- so this
  // scans its source text instead. What that buys is one thing: the app bar
  // dropping ChatCallButtons, which is the regression that would silently take
  // calling away from every DM.
  //
  // It is a substring scan and sees nothing else. An inline call button added
  // back at the site is caught only if it is written with one of the two icon
  // literals below; the same button reached through a helper or a wrapper
  // widget, given a different or aliased icon, or made a text button, passes
  // this untouched. It does not check that anything renders.
  test('the chat header still lists ChatCallButtons in its app bar actions', () {
    final source = File('lib/routes/chat/chat_view.dart').readAsStringSync();
    final start = source.indexOf('List<Widget> _appBarActions(');
    expect(start, greaterThan(-1), reason: '_appBarActions must still exist');
    final body = source.substring(start, source.indexOf('\n  }', start));

    expect(
      body.contains('ChatCallButtons('),
      isTrue,
      reason: 'the app bar must still list the gated buttons in its actions',
    );
    for (final inlined in ['Icons.call_outlined', 'Icons.videocam_outlined']) {
      expect(
        body.contains(inlined),
        isFalse,
        reason:
            'a call button written here with this icon would bypass the gate; '
            'one written any other way is past what this scan can see',
      );
    }
  });
}
