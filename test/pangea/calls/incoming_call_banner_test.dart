import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/incoming_call_banner.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

import 'package:fluffychat/routes/chat/calls/call_service.dart'
    show RejoinOffer;

/// Skips `initMatrix()` — push, notification listeners and the Pangea
/// controller are all irrelevant here and none of them stand up under
/// `flutter test`. The banner only wants `Matrix.of(context).callService`.
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

  const me = '@test:fakeServer.notExisting';
  const caller = '@friend:fakeServer.notExisting';
  const roomId = '!call:fakeServer.notExisting';

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // Avatar reads BotName.byEnvironment, which needs GetStorage and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('call_banner');
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
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// A direct chat, because only a direct chat rings.
  Room directChat() {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        caller: [roomId],
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

  /// A decline sent by THIS account — from another of its devices, which is
  /// what answering on a second phone looks like from here.
  Event ownDecline(Room room, {String refersTo = '\$ring'}) => Event(
    type: PangeaEventTypes.callDecline,
    content: {
      'm.relates_to': {'rel_type': 'm.reference', 'event_id': refersTo},
    },
    senderId: me,
    eventId: '\$decline',
    originServerTs: DateTime.now(),
    room: room,
  );

  /// Writes the caller's call membership into room state, or empties it.
  ///
  /// Emptying is exactly what a caller who gives up does: there is no explicit
  /// cancel event, only the membership going away.
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

  /// Pumped twice: the banner subscribes in a post-frame callback, so nothing
  /// sent before that frame has run would reach it.
  Future<void> pumpBanner(WidgetTester tester) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: IncomingCallBanner(child: SizedBox.shrink()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a caller who hangs up and tries again', () {
    testWidgets('gets the prompt pointed at the new call', (tester) async {
      final room = directChat();
      await pumpBanner(tester);

      client.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('\$ring')), findsOneWidget);

      // The redial. A card still pointing at the first ring answers a call that
      // is already over, and declines it to a caller no longer listening for
      // that one.
      client.onTimelineEvent.add(ring(room, id: '\$redial'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('\$redial')), findsOneWidget);
      expect(find.byKey(const ValueKey('\$ring')), findsNothing);
    });
  });

  group('two rings for one room, replayed out of order', () {
    // The startup replay hands rings over newest-first, so the OLDER one
    // arrives second. Letting any same-room ring replace the one on screen
    // meant a cancelled first attempt overwrote the live redial, and the
    // learner then answered a call that was already over -- the wrong
    // notification id, pointed at a membership nobody holds.
    testWidgets('the older one cannot take the screen', (tester) async {
      final room = directChat();
      await pumpBanner(tester);

      client.onTimelineEvent.add(ring(room, id: '\$redial'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('\$redial')), findsOneWidget);

      client.onTimelineEvent.add(
        ring(room, id: '\$stale', age: const Duration(seconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('\$redial')),
        findsOneWidget,
        reason: 'the live redial keeps the screen',
      );
      expect(find.byKey(const ValueKey('\$stale')), findsNothing);
    });
  });

  group('a call answered on another device', () {
    testWidgets('stops this one offering to answer it', (tester) async {
      final room = directChat();
      await pumpBanner(tester);

      client.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('\$ring')),
        findsOneWidget,
        reason: 'the prompt is up before anything turns the call down',
      );

      // Turned down on another of this account's phones. The caller is already
      // tearing the call down, so going on offering Answer here offers
      // something that no longer exists.
      client.onTimelineEvent.add(ownDecline(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('\$ring')), findsNothing);
    });

    testWidgets('and a ring still in flight cannot put it back', (
      tester,
    ) async {
      final room = directChat();
      await pumpBanner(tester);

      client.onTimelineEvent.add(ownDecline(room));
      await tester.pumpAndSettle();
      // The same ring arriving late — a decline can beat its own notification
      // through the timeline on a second device.
      client.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('\$ring')), findsNothing);
    });
  });
  group('a caller who gives up before anyone answers', () {
    testWidgets('takes the prompt away with them', (tester) async {
      // Cancelling an unanswered call sends nothing that says so. Without
      // watching the membership, the prompt rang on for the rest of its
      // lifetime and answering it joined a call already walked out of.
      final room = directChat();
      callerMembership(room, present: true);
      await pumpBanner(tester);

      client.onTimelineEvent.add(ring(room));
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

    testWidgets('but a membership never seen present does not silence it', (
      tester,
    ) async {
      // Room state may not have synced when a ring lands. Treating "not there
      // yet" as "gone" would silence real calls -- the failure that matters
      // most -- so absence only counts after presence was actually observed.
      final room = directChat();
      await pumpBanner(tester);

      client.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(r'$ring')), findsOneWidget);

      callerMembership(room, present: false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey(r'$ring')),
        findsOneWidget,
        reason: 'never seen present, so this proves nothing about the caller',
      );
    });
  });

  group('mounted where the app really mounts it', () {
    /// Production puts this banner in MaterialApp's BUILDER, above the
    /// router's Navigator -- so nothing inside it has an Overlay ancestor.
    /// Every earlier test pumped it under a Scaffold, which does have one,
    /// and that difference hid a crash that reached a real phone: a Tooltip
    /// in the return card threw "No Overlay widget found", the whole banner
    /// subtree failed, and because the RING card lives in the same Stack, an
    /// incoming call could not be answered at all.
    Future<MatrixState> pumpAsProduction(WidgetTester tester) async {
      await tester.pumpWidget(
        _TestMatrix(
          clients: [client],
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
      // Twice: the banner subscribes in a post-frame callback, so a ring
      // sent before that frame has run reaches nobody.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return tester.state<MatrixState>(find.byType(_TestMatrix));
    }

    /// The three rules this banner keeps relearning, asserted on the real
    /// widget tree rather than trusted to review.
    ///
    /// On the CanvasKit web renderer a Material carrying elevation or a clip
    /// repaints its whole region as an opaque grey rectangle whenever a child
    /// changes -- and a hover is a child changing; a Tooltip brings an
    /// overlay that does the same, and up here it has no Overlay to live in
    /// at all. Every grey-box report against this banner (quick replies, the
    /// answer controls, and now the return offer) has been one of these.
    void expectNoGreyBoxRisk(WidgetTester tester, Finder scope) {
      expect(
        find.descendant(of: scope, matching: find.byType(Tooltip)),
        findsNothing,
        reason: 'a Tooltip paints grey on hover, and has no Overlay here',
      );
      expect(
        find.descendant(of: scope, matching: find.byType(AnimatedSize)),
        findsNothing,
        reason: 'its clip repaints grey on any hover',
      );
      final materials = tester
          .widgetList<Material>(
            find.descendant(of: scope, matching: find.byType(Material)),
          )
          .toList();
      // The convention itself, because the states that go grey are not
      // reachable in a widget test: Material's own buttons animate elevation
      // and manage a clip on hover, and every grey-box report against this
      // banner has come from one of them. The banner builds flat controls
      // instead -- a plain Material with an InkWell -- so their ABSENCE is
      // the thing worth asserting.
      // Named precisely: these carry the elevation (and IconButton the ink
      // clip and a tooltip slot) that the grey box comes from. TextButton is
      // deliberately absent -- it brings neither, and the quick replies have
      // shipped on it since the earlier grey was fixed by removing the
      // clipped, elevated Material around them.
      for (final forbidden in [
        find.byType(FilledButton),
        find.byType(ElevatedButton),
        find.byType(IconButton),
      ]) {
        expect(
          find.descendant(of: scope, matching: forbidden),
          findsNothing,
          reason:
              'Material buttons animate elevation and a clip on hover, which '
              'is the grey box; build the control flat, as _FlatAction and '
              '_CircleAction do',
        );
      }
      for (final m in materials) {
        // ELEVATION is the trigger, and elevation WITH a clip is the reported
        // failure verbatim: "a clipped, elevated Material repaints its whole
        // clip region as an opaque grey rectangle". A plain clip with no
        // elevation is just a rounded avatar and has never gone grey, so the
        // rule stays on the thing that actually breaks.
        expect(
          m.elevation,
          0.0,
          reason:
              'an elevated Material repaints its region grey on hover; '
              'clipBehavior=${m.clipBehavior}',
        );
      }
    }

    testWidgets('the return card offers a way OUT, not just a way back', (
      tester,
    ) async {
      // Dismissing used to only hide the banner, leaving our membership
      // standing while the other person watched their reconnecting window
      // run down for someone who had already decided not to return.
      final room = directChat();
      final state = await pumpAsProduction(tester);
      state.rejoinOffer.value = RejoinOffer(
        room: room,
        membershipEventId: r'$anchor',
        since: DateTime.now(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.descendant(
          of: find.byKey(const ValueKey(r'$anchor')),
          matching: find.byIcon(Icons.call_end),
        ),
        findsOneWidget,
        reason: 'saying no is an answer, and it has to be reachable',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(r'$anchor')),
          matching: find.byIcon(Icons.call),
        ),
        findsOneWidget,
        reason: 'and so is coming back',
      );
    });

    testWidgets('the return card risks no grey box', (tester) async {
      final room = directChat();
      final state = await pumpAsProduction(tester);
      state.rejoinOffer.value = RejoinOffer(
        room: room,
        membershipEventId: r'$anchor',
        since: DateTime.now(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expectNoGreyBoxRisk(tester, find.byKey(const ValueKey(r'$anchor')));
    });

    testWidgets('the ring card risks no grey box either', (tester) async {
      final room = directChat();
      await pumpAsProduction(tester);
      client.onTimelineEvent.add(ring(room));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expectNoGreyBoxRisk(tester, find.byKey(const ValueKey(r'$ring')));
    });

    testWidgets('hovering the return card changes nothing structural', (
      tester,
    ) async {
      // The report was "I hovered and the grey thing came up". A widget test
      // cannot see the renderer's grey, but it CAN prove the hover produces
      // no exception and no new elevated or clipped Material -- which is what
      // the grey actually is.
      final room = directChat();
      final state = await pumpAsProduction(tester);
      state.rejoinOffer.value = RejoinOffer(
        room: room,
        membershipEventId: r'$anchor',
        since: DateTime.now(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      for (final target in [
        find.byIcon(Icons.call),
        find.byIcon(Icons.close),
        find.byKey(const ValueKey(r'$anchor')),
      ]) {
        if (target.evaluate().isEmpty) continue;
        await gesture.moveTo(tester.getCenter(target));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expectNoGreyBoxRisk(tester, find.byKey(const ValueKey(r'$anchor')));
      }
    });

    testWidgets('the return offer renders with no Overlay in scope', (
      tester,
    ) async {
      final room = directChat();
      final state = await pumpAsProduction(tester);

      state.rejoinOffer.value = RejoinOffer(
        room: room,
        membershipEventId: r'$anchor',
        since: DateTime.now(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.takeException(),
        isNull,
        reason:
            'anything that needs an Overlay takes the whole banner down, '
            'including the ring card beside it',
      );
      expect(find.byKey(const ValueKey(r'$anchor')), findsOneWidget);
    });

    testWidgets('a ring renders with no Overlay in scope', (tester) async {
      final room = directChat();
      await pumpAsProduction(tester);

      client.onTimelineEvent.add(ring(room));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey(r'$ring')), findsOneWidget);
    });
  });
}
