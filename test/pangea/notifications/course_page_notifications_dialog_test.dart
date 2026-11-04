import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/notifications/enable_notifications_dialog.dart';
import 'package:fluffychat/features/notifications/notifications_request_repo.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_controller.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_leaderboard_preview.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';
import '../settle_leaderboard.dart';
import '../tutorials/fake_tutorial_progress.dart';

/// #9695 — the course tutorial and the notifications dialog opened together
/// on a course page. The dialog gives way: while a tutorial is running or
/// about to start there, that visit gets no dialog, and the visit does not
/// count as having seen it (get-the-app.instructions.md).

/// Skips `initMatrix()`: the page only needs a client and a navigator.
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
    super.key,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// The tutorial backfill reads the signed-in user off the live [MatrixState].
class _CoursePageTestPangeaController extends FakePangeaController {
  final GlobalKey<MatrixState> matrixKey;

  _CoursePageTestPangeaController(this.matrixKey);

  @override
  MatrixState get matrixState => matrixKey.currentState!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const spaceId = '!course:fakeServer.notExisting';
  const courseTutorialsSeen = {TutorialEnum.welcome, TutorialEnum.coursePlan};
  final matrixKey = GlobalKey<MatrixState>();
  final appTutorials = MatrixState.tutorialOverlayController;

  late Client client;
  late Room room;
  late SharedPreferences store;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('course_page_notif');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async => tempDir.path,
    );
    // Notifications not allowed (0 = denied), so the page asks.
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (methodCall) async => 0,
    );
    // The Mission circles' click sound builds an audioplayers player, which
    // has no platform here; its channels carry a per-player id.
    messenger.allMessagesHandler = (channel, handler, message) =>
        channel.startsWith('xyz.luan/audioplayers')
        ? Future.value(const StandardMethodCodec().encodeSuccessEnvelope(null))
        : handler?.call(message);
    // The dialog's image cache keeps its index in sqflite, which has no
    // platform channel here.
    databaseFactory = databaseFactoryFfi;
    await GetStorage.init('env_override');
    await GetStorage.init('notifications_request_storage');
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    final pangeaController = _CoursePageTestPangeaController(matrixKey);
    // The profile has loaded, so tutorial progress can answer.
    pangeaController.userController.initCompleter.complete();
    MatrixState.pangeaController = pangeaController;
  });

  setUp(() async {
    await GetStorage('notifications_request_storage').erase();
    client = await getTestClient();
    room = Room(id: spaceId, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
        stateKey: '',
        senderId: userId,
        eventId: '\$create',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    client.rooms.add(room);
  });

  tearDown(() async {
    MatrixState.tutorialOverlayController = appTutorials;
    await client.dispose();
  });

  Future<void> openCoursePage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/?c=${Uri.encodeComponent(spaceId)}&left=course',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: SpaceDetails(room: room),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _TestMatrix(
        key: matrixKey,
        clients: [client],
        store: store,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      ),
    );
    await settle(tester, find.byType(CourseLeaderboardPreview));
    // The permission check and the storage read run on real time.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<bool?> dialogCanShow(WidgetTester tester) =>
      tester.runAsync(() => NotificationsRequestRepo.canShowRequest(userId));

  testWidgets(
    'the course tutorial still to come: no dialog on that visit, and it comes '
    'back on a later visit once the tutorial is done',
    timeout: const Timeout(Duration(seconds: 60)),
    (tester) async {
      MatrixState.tutorialOverlayController = TutorialOverlayController(
        progress: const FakeTutorialProgress(),
      );
      await openCoursePage(tester);
      expect(find.byType(EnableNotificationsDialog), findsNothing);
      expect(
        await dialogCanShow(tester),
        isTrue,
        reason: 'a dialog that never showed is not counted as seen',
      );

      // The tutorial is done; the learner leaves and comes back.
      await tester.pumpWidget(const SizedBox());
      MatrixState.tutorialOverlayController = TutorialOverlayController(
        progress: const FakeTutorialProgress(seen: courseTutorialsSeen),
      );
      await openCoursePage(tester);
      expect(find.byType(EnableNotificationsDialog), findsOneWidget);
      // The dialog's image cache schedules a cleanup ten seconds out.
      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'another tutorial under way: no dialog',
    timeout: const Timeout(Duration(seconds: 60)),
    (tester) async {
      final tutorials = TutorialOverlayController(
        progress: const FakeTutorialProgress(seen: courseTutorialsSeen),
      );
      expect(
        tutorials.requestSequence(TutorialSequences.worldOrientationSequence),
        isTrue,
      );
      MatrixState.tutorialOverlayController = tutorials;
      await openCoursePage(tester);
      expect(find.byType(EnableNotificationsDialog), findsNothing);
    },
  );
}
