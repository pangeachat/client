import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';
import 'package:fluffychat/routes/world/course_context_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// #8736 — with a course selected and its panel closed, the map's search slot
/// carries the course context bar instead: the scoped map has to say WHICH
/// course scopes it, or a learner starts a course activity believing they are
/// on the world map. The bar is the closed panel's header — name, actions,
/// progress — and it is the way back into the card, so:
///
/// - it names the selected course and shows that course's progress,
/// - tapping it (anywhere but its actions) reopens the course card over the
///   same `?c=` context,
/// - it carries NO close control: `?c=` is cleared by the World control, never
///   by dismissing the thing that reports it.

/// Skips `initMatrix()` — the bar only wants a routed, localized subtree with
/// a client on it.
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

  const userId = '@test:fakeServer.notExisting';
  const spaceId = '!course:fakeServer.notExisting';
  const courseName = 'Español 101';

  late Client client;
  late SharedPreferences store;
  late GoRouter router;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('course_context_bar');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
    final room = Room(id: spaceId, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': courseName},
        stateKey: '',
        senderId: userId,
        eventId: '\$name',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    client.rooms.add(room);
  });

  tearDown(() async {
    await client.dispose();
  });

  /// The bar as the map mounts it: a course-scoped workspace (`?c=`) with no
  /// course panel in `?left=` — the state it exists for.
  Future<void> pumpBar(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/?c=${Uri.encodeComponent(spaceId)}&left=chats',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: CourseContextBar(spaceId: spaceId)),
        ),
      ],
    );
    await tester.pumpWidget(
      _TestMatrix(
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
    // The L10n delegate resolves asynchronously — a single pumped frame leaves
    // the Localizations subtree empty, which would pass the negative case here
    // for the wrong reason.
    await tester.pumpAndSettle();
  }

  testWidgets('names the selected course and shows its progress', (
    tester,
  ) async {
    await pumpBar(tester);

    expect(find.text(courseName), findsOneWidget);
    expect(find.byType(CourseProgressBar), findsOneWidget);
  });

  testWidgets('tapping it reopens the course card over the same context', (
    tester,
  ) async {
    await pumpBar(tester);

    await tester.tap(find.text(courseName));
    await tester.pumpAndSettle();

    final uri = router.routerDelegate.currentConfiguration.uri;
    expect(
      parseOpenPanels(uri).left.any((t) => t.type == PanelTypesEnum.course),
      isTrue,
      reason: 'the bar is the way back into the course card',
    );
    // The context is a scope, not a panel: reopening the card must not disturb
    // it (routing.instructions.md → The course context).
    expect(activeSpaceIdFor(uri), spaceId);
  });

  testWidgets('carries no close control', (tester) async {
    await pumpBar(tester);

    expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
    expect(find.byType(BackButton), findsNothing);
  });
}
