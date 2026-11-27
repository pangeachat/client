import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/course_access/course_access.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/course_access_sheet.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';
import '../settle_participants.dart';
import '../tutorials/fake_tutorial_progress.dart';

/// The "Who can join?" row in a course's More section reads the course's
/// setting when the page opens. Another admin or device can change it while
/// the page stays open, so tapping the row reads it again: the sheet opens on
/// what the course has now, and Done applies a choice that differs from that
/// (joining-courses.instructions.md § Course access).

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
  final matrixKey = GlobalKey<MatrixState>();
  final appTutorials = MatrixState.tutorialOverlayController;

  late _DirectoryServer server;
  late Client client;
  late Room room;
  late SharedPreferences store;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('course_access_more');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async => tempDir.path,
    );
    // Notifications allowed (1 = granted), so the page does not ask.
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (methodCall) async => 1,
    );
    messenger.allMessagesHandler = (channel, handler, message) =>
        channel.startsWith('xyz.luan/audioplayers')
        ? Future.value(const StandardMethodCodec().encodeSuccessEnvelope(null))
        : handler?.call(message);
    databaseFactory = databaseFactoryFfi;
    await GetStorage.init('env_override');
    await GetStorage.init('notifications_request_storage');
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    final pangeaController = _CoursePageTestPangeaController(matrixKey);
    pangeaController.userController.initCompleter.complete();
    MatrixState.pangeaController = pangeaController;
  });

  setUp(() async {
    // The course tutorials are done, so no overlay covers the page.
    MatrixState.tutorialOverlayController = TutorialOverlayController(
      progress: const FakeTutorialProgress(
        seen: {TutorialEnum.welcome, TutorialEnum.coursePlan},
      ),
    );
    server = _DirectoryServer();
    client = await getTestClient(httpClient: server);
    room = Room(id: spaceId, client: client, membership: Membership.join);
    for (final (type, content) in [
      (EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace}),
      (
        EventTypes.RoomPowerLevels,
        {
          'users': {userId: 100},
        },
      ),
      (EventTypes.RoomJoinRules, {'join_rule': 'knock'}),
    ]) {
      room.setState(
        Event(
          type: type,
          content: content,
          stateKey: '',
          senderId: userId,
          eventId: '\$$type',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
    }
    client.rooms.add(room);
  });

  tearDown(() async {
    MatrixState.tutorialOverlayController = appTutorials;
    await client.dispose();
  });

  /// Lets the client's requests, which run on real time, answer.
  Future<void> letRequestsAnswer(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<void> openMoreSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SizedBox(
              width: 600,
              height: 700,
              child: SpaceDetails(
                room: room,
                activeTab: SpaceSettingsTabs.more,
                expandedSection: true,
              ),
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
    await settle(tester, find.text('Who can join?'));
    await letRequestsAnswer(tester);
  }

  testWidgets(
    'a change made elsewhere since the page opened: the sheet opens on it, '
    'and picking the earlier setting applies it',
    timeout: const Timeout(Duration(seconds: 60)),
    (tester) async {
      server.visibility = 'public';
      await openMoreSection(tester);
      expect(find.text('Approval required'), findsOneWidget);

      // Another admin unlists the course; the join rule stays knock.
      server.visibility = 'private';

      await tester.tap(find.text('Who can join?'));
      await letRequestsAnswer(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CourseAccessSheet), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<CourseAccess>>(
              find.byType(RadioGroup<CourseAccess>),
            )
            .groupValue,
        CourseAccess.private,
        reason: 'the sheet shows the course now',
      );

      await tester.tap(find.text('Approval required').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await letRequestsAnswer(tester);
      await tester.pumpAndSettle();

      expect(server.writes, ['directory:public']);
    },
  );
}

/// Answers the course's directory listing from [visibility] and records the
/// access writes; everything else goes to [FakeMatrixApi].
class _DirectoryServer extends http.BaseClient {
  final FakeMatrixApi _fallback = FakeMatrixApi();
  final List<String> writes = [];
  String visibility = 'private';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = Uri.decodeFull(request.url.path);
    if (path.contains('/directory/list/room/')) {
      if (request.method == 'PUT') {
        visibility =
            jsonDecode((request as http.Request).body)['visibility'] as String;
        writes.add('directory:$visibility');
        return _json({});
      }
      return _json({'visibility': visibility});
    }
    if (request.method == 'PUT' && path.contains('/state/m.room.join_rules')) {
      writes.add('join_rules');
      return _json({'event_id': '\$new'});
    }
    return _fallback.send(request);
  }

  http.StreamedResponse _json(Map<String, dynamic> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: {'content-type': 'application/json'},
      );
}
