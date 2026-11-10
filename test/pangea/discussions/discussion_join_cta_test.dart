import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/discussions/discussion_join_exceptions.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/discussions/discussion_join_cta.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../activity_session_fixtures.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// The Join button of a discussion's start page (#9647): which course's room
/// it reads and joins, how often it reads, and what a learner removed from
/// the room sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const path = '/_synapse/client/pangea/v1/discussion_room';
  const activityId = testSessionActivityId;
  const courseA = '!courseA:fakeServer.notExisting';
  const courseB = '!courseB:fakeServer.notExisting';

  late Client client;
  late SharedPreferences store;
  late List<Uri> previews;
  late http.Response Function(Uri) answer;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=$testDiscussionBotId');
    final tempDir = await Directory.systemTemp.createTemp('discussion_cta');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  setUp(() async {
    previews = [];
    answer = (_) => _json({'students': 2});
    client = await getTestClient(
      httpClient: _PreviewServer(path, (uri) {
        previews.add(uri);
        return answer(uri);
      }),
    );
    MatrixState.pangeaController = FakePangeaController(client: client);
  });

  tearDown(() async {
    await client.dispose();
  });

  Room courseSpace(String id) {
    final space = Room(id: id, client: client, membership: Membership.join);
    space.setState(
      activitySessionStateEvent(
        space,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    space.setState(
      activitySessionStateEvent(
        space,
        type: PangeaEventTypes.coursePlan,
        content: CoursePlanEvent(uuid: 'quest-$id', l2: 'es').toJson(),
      ),
    );
    return space;
  }

  Widget cta(Room? course) => _TestMatrix(
    clients: [client],
    store: store,
    client: client,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: DiscussionJoinCta(
          course: course,
          activityId: activityId,
          activity: discussionActivityPlan(),
        ),
      ),
    ),
  );

  /// Lets the page's localizations load and a read's request and answer
  /// land.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  String? courseOf(Uri uri) => uri.queryParameters['course_id'];

  testWidgets('a new course on the same page reads, and would join, that '
      'course\'s room', (tester) async {
    answer = (uri) => _json({'students': courseOf(uri) == courseA ? 2 : 5});
    final a = courseSpace(courseA);
    final b = courseSpace(courseB);

    await tester.pumpWidget(cta(a));
    await settle(tester);
    expect(find.text('2 classmates are in this discussion'), findsOneWidget);

    await tester.pumpWidget(cta(b));
    await settle(tester);
    expect(courseOf(previews.last), courseB);
    expect(find.text('5 classmates are in this discussion'), findsOneWidget);
  });

  testWidgets('a learner removed from the room is told they can\'t join, '
      'with no Join and no more reads', (tester) async {
    answer = (_) => _json({'errcode': DiscussionRemovedException.errcode}, 403);
    await tester.pumpWidget(cta(courseSpace(courseA)));
    await settle(tester);

    expect(find.text("You can't join this discussion."), findsOneWidget);
    expect(find.text('Join the discussion'), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await settle(tester);
    expect(previews, hasLength(1));
  });

  testWidgets('a rate-limited read waits twice as long before the next one', (
    tester,
  ) async {
    answer = (_) => _json({'errcode': 'M_LIMIT_EXCEEDED'}, 429);
    await tester.pumpWidget(cta(courseSpace(courseA)));
    await settle(tester);
    expect(previews, hasLength(1));

    // The usual 5 seconds pass without a read.
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    expect(previews, hasLength(1));

    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(previews, hasLength(2));
  });

  testWidgets('nothing is read while the app is hidden, and a read runs '
      'as it comes back', (tester) async {
    await tester.pumpWidget(cta(courseSpace(courseA)));
    await settle(tester);
    expect(previews, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 30));
    await settle(tester);
    expect(previews, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(previews, hasLength(2));
  });

  testWidgets('without a course, the course holding the learner\'s seat is '
      'asked first', (tester) async {
    client.rooms.addAll([courseSpace(courseA), courseSpace(courseB)]);
    client.rooms.add(
      discussionRoom(
        client,
        courseId: courseB,
        seats: [discussionSeat(testSessionUserId)],
      ),
    );
    await tester.pumpWidget(cta(null));
    await settle(tester);
    expect(courseOf(previews.first), courseB);
  });

  testWidgets('without a course, a course joined after the page opened is '
      'asked', (tester) async {
    await tester.pumpWidget(cta(null));
    await settle(tester);
    expect(previews, isEmpty);

    client.rooms.add(courseSpace(courseA));
    client.onSync.add(SyncUpdate(nextBatch: 'joined-a-course'));
    await settle(tester);
    expect(courseOf(previews.single), courseA);
    expect(find.text('2 classmates are in this discussion'), findsOneWidget);
  });
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// Answers the discussion preview with [handle] and passes everything else
/// (login) to a [FakeMatrixApi].
class _PreviewServer extends http.BaseClient {
  final String path;
  final http.Response Function(Uri) handle;
  final FakeMatrixApi _matrix = FakeMatrixApi();

  _PreviewServer(this.path, this.handle);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path != path) return _matrix.send(request);
    final response = handle(request.url);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// Skips `initMatrix()`; the button only wants `Matrix.of(context).client`.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}

  @override
  Client get client => (widget as _TestMatrix).client;
}

class _TestMatrix extends Matrix {
  final Client client;

  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
    required this.client,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}
