import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/bot_join_error_dialog.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'get_test_client.dart';
import 'sentry_capture_harness.dart';

/// CLIENT-EJY: the "Play with Pangea Bot" loading dialog waits on `/sync` for
/// the bot to take its seat and then pops itself. A learner who dismissed the
/// dialog while it waited left that pop running on a disposed State, which
/// threw `Null check operator used on a null value` — into the dialog's own
/// catch, which reported it to Sentry. Dismissing changes nothing about the
/// session — the bot marker is already written, so the bot still joins and
/// the start page moves on — it just must not report anything, and must not
/// pop the page underneath in the dialog's place.
void main() {
  const botId = '@pangeabot:fakeServer.notExisting';
  // FakeMatrixApi's magic room id — the only room whose state PUTs
  // (`addBotToActivity`) the fake homeserver accepts.
  const roomId = '!1234:fakeServer.notExisting';

  late Client client;
  late _SeatedBotRoom room;
  late SentryCaptureHarness sentry;

  setUpAll(() async {
    // `BotName.byEnvironment` reads the GetStorage-backed environment override
    // before dotenv, and GetStorage (and BotFace's image cache) need a
    // path_provider directory to open.
    final tempDir = Directory.systemTemp.createTempSync('bot_join_dialog');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': botId});
    // BotFace's image cache keeps its index in sqflite, which has no platform
    // channel here; point it at the ffi factory so it opens instead of
    // throwing mid-test.
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    client = await getTestClient();
    room = _SeatedBotRoom(id: roomId, client: client, botId: botId);
    sentry = SentryCaptureHarness();
    await sentry.init();
  });

  tearDown(() async {
    await sentry.close();
    await client.dispose();
  });

  /// The dialog's BotFace fails its Rive file load in the test VM (no native
  /// library) as an uncaught async error, which would end the test body on
  /// the spot. A widget's futures belong to the zone that built it, so build
  /// the dialog under a guard that drops Rive's failure and hands anything
  /// else — the pop under test included — to the binding, where
  /// `takeException` reads it.
  Future<void> pumpUnderGuard(WidgetTester tester, [Duration? duration]) =>
      runZonedGuarded(() => tester.pump(duration), (e, s) {
        if ('$e$s'.contains('rive_native')) return;
        FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s));
      })!;

  /// A page with one button that opens the dialog. Pumped under the fake
  /// clock, which is what lets the localizations load before the first tap.
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => PlayWithBotLoadingDialog(room: room),
              ),
              child: const Text('play with bot'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the dialog and returns once its join flow has written the bot
  /// marker and checked membership — from here on the only thing it waits on
  /// is the bot's seat arriving on `/sync`.
  ///
  /// Call inside [WidgetTester.runAsync]: the join flow round-trips the fake
  /// homeserver, which the tester's fake clock never advances.
  Future<void> openDialog(WidgetTester tester) async {
    // Plain pumps from here: the dialog's progress indicator animates
    // forever, so pumpAndSettle would never settle.
    await tester.tap(find.text('play with bot'));
    await pumpUnderGuard(tester);
    await pumpUnderGuard(tester, const Duration(milliseconds: 300));
    expect(find.byType(PlayWithBotLoadingDialog), findsOneWidget);
    await room.participantsRequested.future;
  }

  /// The bot takes its seat and the next sync lands. Returns once the
  /// dialog's reaction to it — the pop under test — has fully run.
  Future<void> seatBot(WidgetTester tester) async {
    room.setState(
      Event(
        type: PangeaEventTypes.activityRole,
        content: ActivityRolesModel({
          'role-1': ActivityRoleModel(id: 'role-1', userId: botId, role: 'Bot'),
        }).toJson(),
        senderId: botId,
        eventId: '\$role',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: room,
      ),
    );
    client.onSync.add(SyncUpdate(nextBatch: 'bot-seated'));
    // A zero-length timer fires only once every pending microtask has run,
    // which is the whole sync → seat check → pop chain.
    await Future<void>.delayed(Duration.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Then give any report the chain started time to reach the harness before
    // the caller asserts none was made. `logError` does not await
    // `Sentry.captureException`, so `beforeSend` runs turns later: without
    // this, "no event captured" also passes when an event simply had not
    // landed yet. That is how these assertions stayed green on CI while
    // failing locally, and it is a false green — the direction that hides a
    // regression rather than inventing one.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  testWidgets('the dialog pops itself once the bot takes its seat', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.runAsync(() async {
      await openDialog(tester);
      await seatBot(tester);
    });
    expect(tester.takeException(), isNull);
    expect(sentry.events, isEmpty);
    expect(find.byType(PlayWithBotLoadingDialog), findsNothing);
    expect(find.text('play with bot'), findsOneWidget);
  });

  testWidgets(
    'a dialog dismissed while waiting for the bot does not pop a disposed route',
    (tester) async {
      await pumpPage(tester);
      await tester.runAsync(() async {
        await openDialog(tester);

        // The learner taps outside the dialog while the seat is pending.
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(PlayWithBotLoadingDialog), findsNothing);

        await seatBot(tester);
      });
      expect(tester.takeException(), isNull);
      expect(sentry.events, isEmpty);
      // The page under the dialog is still there — nothing popped in its place.
      expect(find.text('play with bot'), findsOneWidget);
    },
  );
}

/// A session room whose bot is already a joined member, so the dialog's
/// re-invite guard is a no-op and the only thing it waits on is the seat.
class _SeatedBotRoom extends Room {
  _SeatedBotRoom({
    required super.id,
    required super.client,
    required this.botId,
  });

  final String botId;

  /// Completes the first time the dialog checks membership — the last step
  /// of its join flow before it settles in to wait on `/sync`.
  final participantsRequested = Completer<void>();

  @override
  Future<List<User>> requestParticipants([
    List<Membership> membershipFilter = const [
      Membership.join,
      Membership.invite,
      Membership.knock,
    ],
    bool suppressWarning = false,
    bool? cache,
  ]) async {
    if (!participantsRequested.isCompleted) participantsRequested.complete();
    return [User(botId, membership: 'join', room: this)];
  }
}
