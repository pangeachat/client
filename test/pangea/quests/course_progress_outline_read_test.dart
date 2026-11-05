import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' hide Result;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/course_progress_writer.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

/// A progress check reads each course's outline, then writes the course's
/// record: a learner who logs out during the read (#9729, CLIENT-F5M), and a
/// read that fails or is slower than the check waits for (#9774, CLIENT-ERW).
void main() {
  // A reported timeout asks the binding whether the app is in the foreground.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late _ProgressServer server;
  late Room analyticsRoom;
  late List<String> errors;
  final debugPrintBefore = debugPrint;

  const userId = '@test:fakeServer.notExisting';
  const questId = 'quest-1';
  const courseRoomId = '!course:fakeServer.notExisting';
  final de = LanguageModel(langCode: 'de', displayName: 'German');

  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Pangea Chat',
      packageName: 'com.talktolearn.chat',
      version: '5.0.18',
      buildNumber: '1',
      buildSignature: '',
    );
    MatrixState.pangeaController = _Controller(_Users()..userL2 = de);
    MissionXpCache.instance.ensureWired();
    // A refresh asked for while one is in flight runs after it, so one await
    // can return before the cache settles.
    for (var i = 0; i < 3; i++) {
      await MissionXpCache.instance.refresh();
      await Future<void>.delayed(Duration.zero);
    }
    expect(MissionXpCache.instance.hasReadFor('de'), isTrue);
  });

  setUp(() async {
    server = _ProgressServer();
    client = await getTestClient(httpClient: server);
    QuestRepo.resetOutlineCacheForTest();
    QuestRepo.debugDisplayL1 = 'en';
    ErrorHandler.resetReportedOnceKeysForTest();
    errors = [];
    debugPrint = (message, {wrapWidth}) {
      if (message != null && message.startsWith('error message:')) {
        errors.add(message);
      }
    };

    final course = Room(
      id: courseRoomId,
      client: client,
      membership: Membership.join,
    );
    for (final (type, content) in [
      (EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace}),
      (
        PangeaEventTypes.coursePlan,
        CoursePlanEvent(uuid: questId, l2: 'de').toJson(),
      ),
    ]) {
      course.setState(
        Event(
          type: type,
          content: content,
          stateKey: '',
          senderId: userId,
          eventId: '\$$type',
          originServerTs: DateTime.utc(2026, 1, 1),
          room: course,
        ),
      );
    }
    client.rooms.add(course);
    analyticsRoom = Room(
      id: '!analytics:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    )..partial = false;
    client.rooms.add(analyticsRoom);
  });

  tearDown(() async {
    debugPrint = debugPrintBefore;
    QuestRepo.debugBuildOutline = null;
    QuestRepo.debugDisplayL1 = null;
    QuestRepo.resetOutlineCacheForTest();
    await client.dispose();
  });

  QuestOutline outline() => QuestOutline(
    quest: const QuestPlan(
      id: questId,
      name: 'Quest',
      description: '',
      targetLanguage: 'de',
      sequence: [
        QuestObjectiveStep(
          objective: LearningObjective(id: 'lo-1', objective: 'Can greet.'),
          wasMinted: false,
        ),
      ],
    ),
    groups: [
      QuestObjectiveGroup(
        objective: const LearningObjective(id: 'lo-1', objective: 'Can greet.'),
        activities: const [],
      ),
    ],
  );

  CourseProgressWriter writer({
    Duration outlineReadTimeout = const Duration(seconds: 5),
  }) => CourseProgressWriter(
    readUses: (_) async => const [],
    outlineReadTimeout: outlineReadTimeout,
  );

  const reportKey = 'course-progress-outline:$courseRoomId';

  test('a course with no record gets one written', () async {
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) async =>
        Result.value(outline());

    await writer().update(analyticsRoom, 'de');

    expect(server.progressWrites, 1);
    expect(errors, isEmpty);
  });

  test('a logout during the outline read stops the check before its write, '
      'and nothing is reported', () async {
    final readStarted = Completer<void>();
    final read = Completer<Result<QuestOutline>>();
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) {
      readStarted.complete();
      return read.future;
    };

    final check = writer().update(analyticsRoom, 'de');
    await readStarted.future;
    await client.logout();
    read.complete(Result.value(outline()));
    await check;

    expect(server.progressWrites, 0);
    expect(errors, isEmpty);
  });

  test('a failed outline read is reported, and the course is not read again '
      'until its retry', () async {
    var reads = 0;
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
      reads++;
      return Result.error(Exception('outline read failed'));
    };
    final progress = writer();

    await progress.update(analyticsRoom, 'de');
    await progress.update(analyticsRoom, 'de');

    expect(reads, 1);
    expect(server.progressWrites, 0);
    expect(ErrorHandler.reportedOnceKeysForTest, {reportKey});
  });

  group('an outline read slower than the check waits for', () {
    late Completer<Result<QuestOutline>> read;
    late int reads;

    setUp(() {
      read = Completer();
      reads = 0;
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) {
        reads++;
        return read.future;
      };
    });

    test('is not reported, and the course is written once it lands', () async {
      await writer(
        outlineReadTimeout: Duration.zero,
      ).update(analyticsRoom, 'de');

      expect(errors, isEmpty);
      expect(server.progressWrites, 0);

      read.complete(Result.value(outline()));
      await _until(() => server.progressWrites == 1);
      await pumpEventQueue();

      expect(reads, 1);
      expect(errors, isEmpty);
      expect(ErrorHandler.reportedOnceKeysForTest, isEmpty);
    });

    test('that then fails is reported once, and the course waits for its '
        'retry', () async {
      final progress = writer(outlineReadTimeout: Duration.zero);
      await progress.update(analyticsRoom, 'de');

      read.complete(Result.error(Exception('outline read failed')));
      await pumpEventQueue();
      await progress.update(analyticsRoom, 'de');

      expect(reads, 1);
      expect(server.progressWrites, 0);
      expect(errors, [contains('outline read failed')]);
      expect(ErrorHandler.reportedOnceKeysForTest, {reportKey});
    });
  });
}

/// Waits for work a check started on its own, such as the check that runs
/// when a slow outline read lands, to make [done] true.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'the check never got there');
}

/// Answers the progress record's state write itself and counts it; everything
/// else goes to [FakeMatrixApi].
class _ProgressServer extends http.BaseClient {
  final FakeMatrixApi _fallback = FakeMatrixApi();
  int progressWrites = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'PUT' ||
        !request.url.path.contains(
          '/state/${PangeaEventTypes.courseProgress}/',
        )) {
      return _fallback.send(request);
    }
    progressWrites++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'event_id': '\$progress'}))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _Analytics implements AnalyticsDataService {
  @override
  final AnalyticsUpdateDispatcher updateDispatcher = _Dispatcher();

  @override
  Completer<void> initCompleter = Completer<void>()..complete();

  @override
  bool get hasInitError => false;

  @override
  String? get initializedLanguage => 'de';

  @override
  Future<List<OneConstructUse>> getUses(
    String language, {
    int? count,
    String? roomId,
    DateTime? since,
    List<ConstructUseTypeEnum>? types,
    bool filterCapped = true,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Dispatcher implements AnalyticsUpdateDispatcher {
  @override
  final StreamController<AnalyticsStreamUpdate> constructUpdateStream =
      StreamController<AnalyticsStreamUpdate>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Users implements UserController {
  @override
  LanguageModel? userL2;

  @override
  final StreamController<LanguageUpdate> languageStream =
      StreamController<LanguageUpdate>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Matrix implements MatrixState {
  final AnalyticsDataService analytics = _Analytics();

  @override
  AnalyticsDataService? get analyticsServiceIfExists => analytics;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_Matrix';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Controller implements PangeaController {
  _Controller(this.userController);

  @override
  final UserController userController;

  @override
  final MatrixState matrixState = _Matrix();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
