import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/incoming_call_banner.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// The app supports several logged-in accounts, and the incoming-call banner
/// used to listen on the ACTIVE one alone. A call placed to a second account
/// reached nobody: no prompt, no sound, and no trace on the callee's screen,
/// while the caller rang out and wrote a missed-call card.
///
/// Every test here pumps the banner with TWO logged-in clients and makes the
/// SECOND one — never the active one — the account being called.
///
/// KNOWN LIMIT OF THIS FIXTURE. Both clients end up with the SAME Matrix user
/// id: `FakeMatrixApi` returns one canned `/login` response and exposes no way
/// to vary it, so `client.userID` is `@test:fakeServer.notExisting` for both.
/// What separates the accounts here is their `clientName` — which is the key
/// every per-account service is held under — and their streams, which is what
/// the fix actually binds to. So these tests DO prove the banner subscribes
/// per client and acts through the right client's service, and they CANNOT
/// prove anything that turns on two distinct user ids, such as
/// `answeredOnAnotherDevice` filtering room state by `client.userID`. Real
/// two-account behaviour still needs two accounts on a live homeserver.
///
/// Skips `initMatrix()` for the same reason the single-account banner test
/// does: push, notification listeners and the Pangea controller are all
/// irrelevant here and none of them stand up under `flutter test`.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const caller = '@friend:fakeServer.notExisting';
  const roomId = '!call:fakeServer.notExisting';

  /// The account the learner is looking at.
  late Client active;

  /// The other account they are signed in to, and the one being called.
  late Client other;

  /// An account that is NOT in `clients` — a client mid-logout, or one whose
  /// service has already been evicted. Built here rather than inside a test:
  /// `getTestClient` opens a database, and real async work inside
  /// `testWidgets`' fake-async zone never completes.
  late Client departed;
  late SharedPreferences store;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('multi_account_ring');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    // DIFFERENT client names. Every per-account service in MatrixState is held
    // under the client name, so two accounts sharing one would resolve to the
    // same call service and this whole file would prove nothing.
    active = await getTestClient(name: 'active-account');
    other = await getTestClient(name: 'other-account', deviceId: 'OTHERDEVICE');
    departed = await getTestClient(
      name: 'departed-account',
      deviceId: 'GONEDEVICE',
    );
  });

  tearDown(() async {
    await active.dispose();
    await other.dispose();
    await departed.dispose();
  });

  /// A direct chat on [client], because only a direct chat rings.
  Room directChat(Client client, {String id = roomId}) {
    final room = Room(id: id, client: client, membership: Membership.join);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        caller: [id],
      },
    );
    return room;
  }

  /// Built by the sender's own serialiser, so this cannot drift from the shape
  /// a real ring actually has.
  Event ring(Room room, {String id = '\$ring', Duration age = Duration.zero}) =>
      Event(
        type: PangeaEventTypes.callNotification,
        content: const CallNotification(
          membershipEventId: '\$membership',
          senderDeviceId: 'CALLERDEVICE',
          video: false,
        ).toContent(DateTime.now().subtract(age)),
        senderId: caller,
        eventId: id,
        originServerTs: DateTime.now().subtract(age),
        room: room,
      );

  /// Writes the caller's call membership into room state, or empties it.
  ///
  /// Emptying is what a caller who gives up does: there is no explicit cancel
  /// event, only the membership going away. `Room.setState` publishes on
  /// `room.client.onRoomState`, so which client owns the room decides which
  /// stream this reaches — which is exactly what the watcher fix is about.
  void callerMembership(
    Room room, {
    required bool present,
    String id = r'$mem',
  }) {
    room.setState(
      Event(
        type: EventTypes.GroupCallMember,
        content: {
          'memberships': present
              ? [
                  {'call_id': 'call-id', 'device_id': 'CALLERDEVICE'},
                ]
              : <Map<String, dynamic>>[],
        },
        senderId: caller,
        eventId: id,
        originServerTs: DateTime.now(),
        room: room,
        stateKey: caller,
      ),
    );
  }

  /// Mounted where production mounts it — in MaterialApp's builder, above the
  /// router — with BOTH accounts signed in and [active] foregrounded.
  Future<MatrixState> pumpBanner(
    WidgetTester tester, {
    List<Client>? clients,
  }) async {
    final list = clients ?? [active, other];
    await tester.pumpWidget(
      _TestMatrix(
        clients: list,
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) =>
              IncomingCallBanner(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    final state = tester.state<MatrixState>(find.byType(_TestMatrix));
    // The first client is the active one. Without this the active index is
    // -1 and `client` falls back, which is not the state under test.
    state.setActiveClient(list.first);
    // Twice: the banner subscribes in a post-frame callback, so a ring sent
    // before that frame has run reaches nobody.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return state;
  }

  // Every mutation of the account list has to SAY so, or the banner never
  // learns and that account never rings. A widget test can only prove the
  // banner reacts to the signal; it cannot prove production emits it, and a
  // new `clients.add` in some future login path would slip straight past.
  // So the invariant is asserted mechanically against the source, the way
  // this file's sibling asserts the banner's one teardown.
  test('every change to the account list announces itself', () {
    final source = File('lib/widgets/matrix.dart').readAsStringSync();
    final lines = source.split('\n');
    final mutations = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (RegExp(
        r'widget\.clients\.(add|remove|insert|clear)\(',
      ).hasMatch(lines[i])) {
        mutations.add(i);
      }
    }
    expect(
      mutations,
      isNotEmpty,
      reason: 'the list must still be mutated somewhere, or this test is dead',
    );
    for (final at in mutations) {
      // Near the mutation, not merely somewhere in the file: the
      // announcement belongs in the same block, not in a caller that a later
      // edit might stop going through. The window is generous forward because
      // the logout path deliberately says it LAST, once the account is fully
      // out of the way, so a listener that re-reads the list sees it gone.
      final from = (at - 4).clamp(0, lines.length);
      final to = (at + 14).clamp(0, lines.length);
      expect(
        lines.sublist(from, to).any((l) => l.contains('_accountsChanged()')),
        isTrue,
        reason:
            'line ${at + 1} changes the account list without saying so:\n'
            '  ${lines[at].trim()}\n'
            'Nothing below MatrixState rebuilds on an account change, so an '
            'account added here would never be subscribed and never ring.',
      );
    }
  });

  group('the memory of a turned-down call', () {
    test('is dropped once no ring could still be worth suppressing', () {
      // The banner is mounted ONCE for the app's whole life, so anything it
      // remembers per call is remembered for ever unless something drops it.
      // The bound is a ring's longest life: past it `shouldRing` rejects the
      // notification as expired anyway, so the entry cannot change an outcome.
      final now = DateTime.now();
      final seen = {
        r'$fresh': now.subtract(const Duration(seconds: 1)),
        r'$edge': now.subtract(CallNotification.maxLifetime),
        r'$stale': now.subtract(
          CallNotification.maxLifetime + const Duration(seconds: 1),
        ),
      };

      IncomingCallBanner.pruneDeclines(seen, now);

      expect(seen.keys, containsAll([r'$fresh', r'$edge']));
      expect(
        seen.containsKey(r'$stale'),
        isFalse,
        reason: 'a decline older than any ring can only take up room',
      );
    });
  });

  group('a call to a second logged-in account', () {
    testWidgets('rings, even though another account is foregrounded', (
      tester,
    ) async {
      // THE ITEM. The banner subscribed to the active client alone, so this
      // ring reached nobody at all: the learner saw nothing while the caller
      // rang out and wrote a missed call.
      final room = directChat(other);
      await pumpBanner(tester);

      other.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey(r'$ring')),
        findsOneWidget,
        reason: 'a call to any signed-in account has to reach the learner',
      );
    });

    testWidgets('and the active account still rings as it always did', (
      tester,
    ) async {
      final room = directChat(active);
      await pumpBanner(tester);

      active.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(r'$ring')), findsOneWidget);
    });
  });

  group('the prompt for a second account watches that account', () {
    testWidgets('so the caller giving up takes it away', (tester) async {
      // The watchers are the half of this bug that would have bitten
      // silently. `callerPresenceChanges` reads the SERVICE's own client, so
      // run through the ACTIVE account's service it listens to the active
      // client's `onRoomState` -- which never emits for another account's
      // rooms. The prompt would have sat there offering to answer a call the
      // caller had already walked out of, for its whole lifetime.
      final room = directChat(other);
      callerMembership(room, present: true);
      await pumpBanner(tester);

      other.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(r'$ring')), findsOneWidget);

      callerMembership(room, present: false, id: r'$mem2');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey(r'$ring')),
        findsNothing,
        reason: 'the caller is gone, so there is nothing left to answer',
      );
    });

    testWidgets('and a decline it sends puts its own prompt away', (
      tester,
    ) async {
      // `ownDeclines` is per account too. Answering on another of THIS
      // account's devices is what this looks like from here.
      final room = directChat(other);
      await pumpBanner(tester);

      other.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(r'$ring')), findsOneWidget);

      other.onTimelineEvent.add(
        Event(
          type: PangeaEventTypes.callDecline,
          content: {
            'm.relates_to': {'rel_type': 'm.reference', 'event_id': r'$ring'},
          },
          senderId: other.userID!,
          eventId: r'$decline',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(r'$ring')), findsNothing);
    });
  });

  group('two accounts in a room with the same id', () {
    testWidgets('are two conversations, not a redial of each other', (
      tester,
    ) async {
      // A room id is server-global and both accounts can be members of one
      // room. Comparing ids alone, the second account's ring read as a REDIAL
      // of the first and REPLACED the prompt -- so answering joined as the
      // wrong account.
      final mine = directChat(active);
      final theirs = directChat(other);
      await pumpBanner(tester);

      active.onTimelineEvent.add(ring(mine, id: r'$first'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(r'$first')), findsOneWidget);

      other.onTimelineEvent.add(ring(theirs, id: r'$second'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey(r'$first')),
        findsOneWidget,
        reason: 'the prompt already on screen keeps it',
      );
      expect(
        find.byKey(const ValueKey(r'$second')),
        findsNothing,
        reason: "another account's call is not a redial of this one",
      );
    });
  });

  group("resolving an account's call service", () {
    testWidgets('by client object, even when the name resolves to nobody', (
      tester,
    ) async {
      // `callServiceFor(name)` ends in `orElse: () => client`, so a name it
      // cannot place yields the ACTIVE account's service. Everything scoped to
      // one call goes through the object-keyed getter instead, because
      // guessing here means placing, answering or ending a call as somebody
      // else's account.
      //
      // The distinguishing case is an account the list does NOT hold and that
      // has no service cached yet -- a client mid-logout, or one whose service
      // was already evicted. For an account still in `clients` both getters
      // agree, so a test built on one would prove nothing.
      final state = await pumpBanner(tester);

      expect(
        identical(state.callServiceForClient(departed).client, departed),
        isTrue,
        reason: "an account's own service, never the foregrounded account's",
      );
      expect(
        identical(
          state.callServiceForClient(other),
          state.callServiceForClient(other),
        ),
        isTrue,
        reason: 'one service per account: a second VoIP would lose the call',
      );
    });

    testWidgets('a logout does not mark its same-name successor as departing', (
      tester,
    ) async {
      // On web every account shares one client name, so "is this account going
      // away" cannot be answered by name: while the account that LEFT unwinds,
      // a name-keyed answer calls its live successor departing too, and the
      // incoming-call banner stops serving an account that is perfectly fine.
      //
      // Posed with two clients built on the SAME name, which is the one case
      // the rest of this file deliberately avoids.
      // Built directly rather than through `getTestClient`, and NOT logged in:
      // the question is asked of the object and answered from a set, so a
      // login (and the sync it starts) buys nothing and is what made an
      // earlier version of this test hang. Each gets its own in-memory
      // database, so sharing a NAME costs them nothing.
      final state = await pumpBanner(tester);
      Future<Client> sameName() async => Client(
        'shared-name',
        httpClient: FakeMatrixApi(),
        database: await MatrixSdkDatabase.init(
          'test',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
      // Through `runAsync`: `testWidgets` drives a FAKE async zone, and opening
      // a database is real I/O that never completes inside it. The clients the
      // rest of this file uses are built in `setUp`, which is already a real
      // zone, so this is the only place that has to say so.
      final clients = await tester.runAsync(
        () async => [await sameName(), await sameName()],
      );
      final leaving = clients![0];
      final successor = clients[1];

      state.markClientSigningOutForTest(leaving);

      expect(
        state.isSigningOut(leaving),
        isTrue,
        reason: 'the account that is actually leaving',
      );
      expect(
        state.isSigningOut(successor),
        isFalse,
        reason:
            'a live account that merely shares the departing one\'s client '
            'name is not itself departing',
      );
    });

    testWidgets('and the name-keyed getter really does fall back', (
      tester,
    ) async {
      // The behaviour the object-keyed getter exists to avoid, asserted so it
      // stops being a claim in a comment. It is CORRECT for what it was
      // written for -- a rebuild during a single-account logout -- and wrong
      // for anything scoped to one call.
      final state = await pumpBanner(tester);

      expect(
        identical(state.callServiceFor('no-such-account').client, active),
        isTrue,
      );
    });
  });

  group('an account arriving and leaving', () {
    testWidgets('a second account logging in starts ringing', (tester) async {
      // Matrix.clients is a plain list with no change signal, and MatrixState
      // hands back an identical child so its setState never rebuilds this
      // subtree. Without the notifier an account that logs in mid-session is
      // never subscribed, and never rings for the rest of the session.
      final state = await pumpBanner(tester, clients: [active]);

      final room = directChat(other);
      state.widget.clients.add(other);
      state.accounts.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      other.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey(r'$ring')),
        findsOneWidget,
        reason: 'an account that just logged in has to ring too',
      );
    });

    testWidgets('an account signing out takes its prompt with it', (
      tester,
    ) async {
      // A prompt for an account that has signed out cannot be answered or
      // declined by anybody, and everything watching that account's service
      // has to go with it.
      final room = directChat(other);
      final state = await pumpBanner(tester);

      other.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(r'$ring')), findsOneWidget);

      state.widget.clients.remove(other);
      state.accounts.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey(r'$ring')),
        findsNothing,
        reason: 'nobody is left who could answer it',
      );
    });

    testWidgets('a ring already in flight when it goes cannot ring', (
      tester,
    ) async {
      // The reconcile runs a frame LATE. Cancelling a subscription does not
      // unqueue what it has already handed over, so between the account
      // leaving `clients` and the reconcile dropping its record, a ring can
      // still arrive -- and would otherwise raise a prompt, and start it
      // sounding, for an account nobody can answer as.
      final room = directChat(other);
      final state = await pumpBanner(tester);

      // Removed WITHOUT letting the reconcile run: no bump, no pump.
      state.widget.clients.remove(other);
      other.onTimelineEvent.add(ring(room, id: r'$inflight'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey(r'$inflight')),
        findsNothing,
        reason: 'the account is already gone, whatever the map still says',
      );
    });

    testWidgets('and stops listening to it', (tester) async {
      final room = directChat(other);
      final state = await pumpBanner(tester);

      state.widget.clients.remove(other);
      state.accounts.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      other.onTimelineEvent.add(ring(room, id: r'$after'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey(r'$after')),
        findsNothing,
        reason: 'a signed-out account must not raise a prompt',
      );
    });
  });
}
