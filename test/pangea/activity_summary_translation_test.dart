import 'dart:async';
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

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_activity_chat_pangea_controller.dart';
import 'get_test_client.dart';

/// The bot writes each card in the activity's language of instruction. A
/// viewer whose first language differs sees every card translated from that
/// card's own stored row: the card stays loading while its translation is
/// fetched, and a failed translation leaves it as written (#9199, #795;
/// client activities.instructions.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:example.org';
  const userId = '@test:fakeServer.notExisting';
  const coursemate = '@alice:example.org';
  const roomId = '!translate:fakeServer.notExisting';
  const summaryPath = '/choreo/activity_summary';

  late Client client;

  setUpAll(() async {
    dotenv.testLoad(
      fileInput: 'BOT_NAME=$bot\nCHOREO_API=https://api.test.pangea.chat',
    );
    final tempDir = await Directory.systemTemp.createTemp('summary_translate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    // The viewer's first language is English.
    MatrixState.pangeaController = ActivityChatTestPangeaController(
      accessToken: 'syt_test_token',
    );
  });

  setUp(() async => client = await getTestClient());
  tearDown(() => client.dispose());

  /// One learner's card content, as the bot writes it.
  ActivitySummaryResponseModel card(String learner, String text) =>
      ActivitySummaryResponseModel(
        participants: [
          ParticipantSummaryModel(
            participantId: learner,
            feedback: text,
            cefrLevel: 'A2',
            superlatives: const [],
          ),
        ],
        summary: '',
      );

  var stateCount = 0;
  void setState(
    Room room,
    String type,
    String stateKey,
    Map<String, dynamic> content, {
    String sender = userId,
  }) => room.setState(
    Event(
      type: type,
      stateKey: stateKey,
      content: content,
      senderId: sender,
      eventId: '\$state${stateCount++}',
      originServerTs: DateTime.now(),
      room: room,
    ),
  );

  /// A room where the viewer (and, with [withCoursemate], a coursemate) has
  /// finished, and whose bot card is in [langCode], stored under choreo row
  /// [requestHash]. A translation is built against the activity's plan, so
  /// only [withPlan] rooms can fetch one.
  Room finishedRoom({
    required String langCode,
    String? requestHash,
    bool withPlan = false,
    bool withCoursemate = false,
    bool withCard = true,
  }) {
    final room = Room(id: roomId, client: client, membership: Membership.join);

    if (withPlan) {
      setState(
        room,
        PangeaEventTypes.activityPlan,
        '',
        ActivityPlanModel(
          req: ActivityPlanRequest(
            topic: 'cafe',
            mode: 'Roleplay',
            objective: 'order a drink',
            media: MediaEnum.nan,
            cefrLevel: LanguageLevelTypeEnum.a1,
            languageOfInstructions: 'fr',
            targetLanguage: 'es',
            numberOfParticipants: 2,
          ),
          title: 'Au café',
          learningObjective: 'lo',
          instructions: 'i',
          vocab: const [],
          activityId: 'activity-1',
        ).toJson(),
      );
    }
    final roles = {
      'role1': ActivityRoleModel(
        id: 'role1',
        userId: userId,
        role: 'Customer',
        finishedAt: DateTime.utc(2026),
      ),
      if (withCoursemate)
        'role2': ActivityRoleModel(
          id: 'role2',
          userId: coursemate,
          role: 'Barista',
          finishedAt: DateTime.utc(2026),
        ),
    };
    setState(
      room,
      PangeaEventTypes.activityRole,
      '',
      ActivityRolesModel(roles).toJson(),
    );
    setState(room, EventTypes.RoomMember, userId, {'membership': 'join'});
    setState(room, EventTypes.RoomMember, bot, {
      'membership': 'join',
    }, sender: bot);
    if (withCard) {
      setState(
        room,
        PangeaEventTypes.activitySummary,
        ActivitySummaryStateKeys.card(userId),
        ActivitySummaryModel(
          summary: card(userId, 'Bien joué.'),
          langCode: langCode,
          requestHash: requestHash,
          finishedAt: DateTime.utc(2026),
        ).toJson(),
        sender: bot,
      );
    }
    // Already written, so the controller has no analytics to compute.
    setState(
      room,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.learnerAnalytics(userId),
      ActivitySummaryAnalyticsModel().toJson(),
    );
    return room;
  }

  /// Opens the room with choreo answered by [respond], or by [pending] when
  /// given, and returns the controller once any translation has settled, plus
  /// the requests made.
  Future<(ActivityChatController, List<Map<String, dynamic>>)> open(
    Room room, {
    required http.Response Function(http.Request request) respond,
    Future<http.Response>? pending,
  }) async {
    final requests = <Map<String, dynamic>>[];
    late ActivityChatController controller;
    await http.runWithClient(
      () async {
        // A room with a plan also scans its timeline for used vocabulary;
        // let that finish before the test closes the client's database.
        var vocabScanned = room.activityPlan == null;
        controller = ActivityChatController(
          userID: userId,
          room: room,
          inputFocus: FocusNode(),
        );
        controller.usedVocab.addListener(() => vocabScanned = true);
        for (
          var i = 0;
          i < 100 && (controller.summaryView.value.isLoading || !vocabScanned);
          i++
        ) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      },
      () => MockClient((request) async {
        if (request.url.path != summaryPath) {
          return http.Response('', 404, request: request);
        }
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return pending ?? respond(request);
      }),
    );
    addTearDown(controller.dispose);
    return (controller, requests);
  }

  http.Response json(http.Request request, ActivitySummaryResponseModel body) =>
      http.Response(
        jsonEncode(body.toJson()),
        200,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  http.Response translated(http.Request request) =>
      json(request, card(userId, 'Well played.'));

  String? ownFeedback(ActivityChatController controller) =>
      controller.summaryView.value.cardFor(userId)?.participant?.feedback;

  test('translates the learner\'s card into the viewer\'s L1', () async {
    final room = finishedRoom(
      langCode: 'fr',
      requestHash: 'row-translate',
      withPlan: true,
    );

    final (controller, requests) = await open(room, respond: translated);

    expect(ownFeedback(controller), 'Well played.');
    expect(requests, hasLength(1));
    expect(requests.single['source_request_hash'], 'row-translate');
    expect(requests.single['viewer_l1'], 'en');
    expect(
      (requests.single['activity'] as Map)['activity_id'] ??
          (requests.single['activity'] as Map)['activityId'],
      isNotNull,
    );
  });

  test('translates each card from its own row', () async {
    final room = finishedRoom(
      langCode: 'fr',
      requestHash: 'row-own',
      withPlan: true,
      withCoursemate: true,
    );
    setState(
      room,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.card(coursemate),
      ActivitySummaryModel(
        summary: card(coursemate, 'Très bien.'),
        langCode: 'fr',
        requestHash: 'row-coursemate',
      ).toJson(),
      sender: bot,
    );

    final (controller, requests) = await open(
      room,
      respond: (request) {
        final hash = (jsonDecode(request.body) as Map)['source_request_hash'];
        return hash == 'row-coursemate'
            ? json(request, card(coursemate, 'Very good.'))
            : translated(request);
      },
    );

    final view = controller.summaryView.value;
    expect(
      requests.map((r) => r['source_request_hash']),
      unorderedEquals(['row-own', 'row-coursemate']),
    );
    expect(view.cardFor(userId)?.participant?.feedback, 'Well played.');
    expect(view.cardFor(coursemate)?.participant?.feedback, 'Very good.');
  });

  test('translates a room summarized before per-learner cards once, group '
      'text included', () async {
    // A room from before per-learner cards has only the bot's whole-room
    // summary.
    final room = finishedRoom(langCode: 'fr', withPlan: true, withCard: false);
    setState(
      room,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.canonical,
      ActivitySummaryModel(
        summary: ActivitySummaryResponseModel(
          participants: card(userId, 'Bien joué.').participants,
          summary: 'Une bonne conversation.',
        ),
        langCode: 'fr',
        requestHash: 'row-room',
      ).toJson(),
      sender: bot,
    );

    final (controller, requests) = await open(
      room,
      respond: (request) => json(
        request,
        ActivitySummaryResponseModel(
          participants: card(userId, 'Well played.').participants,
          summary: 'A good conversation.',
        ),
      ),
    );

    final view = controller.summaryView.value;
    expect(requests.map((r) => r['source_request_hash']), ['row-room']);
    expect(view.groupSummary, 'A good conversation.');
    expect(ownFeedback(controller), 'Well played.');
  });

  test('keeps the card loading while its translation is fetched', () {
    final room = finishedRoom(langCode: 'fr', requestHash: 'row-pending');
    MatrixState.pangeaController = ActivityChatTestPangeaController(
      accessToken: 'syt_test_token',
    );
    // With no plan in the room, the controller fetches one; nothing answers.
    final controller = http.runWithClient(
      () => ActivityChatController(
        userID: userId,
        room: room,
        inputFocus: FocusNode(),
      ),
      () => MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(controller.dispose);

    // Nothing has answered yet: the viewer sees loading, not the French text.
    final own = controller.summaryView.value.cardFor(userId)!;
    expect(own.isLoading, isTrue);
    expect(own.participant, isNull);
  });

  test('a failed translation shows the card as written', () async {
    final room = finishedRoom(
      langCode: 'fr',
      requestHash: 'row-fails',
      withPlan: true,
    );

    final (controller, requests) = await open(
      room,
      respond: (request) => http.Response('', 500, request: request),
    );

    final own = controller.summaryView.value.cardFor(userId)!;
    expect(requests, hasLength(1));
    expect(own.isLoading, isFalse);
    expect(own.hasFailed, isFalse);
    expect(own.participant?.feedback, 'Bien joué.');
  });

  test('a translation that never answers shows the card as written', () async {
    final room = finishedRoom(
      langCode: 'fr',
      requestHash: 'row-hangs',
      withPlan: true,
    );
    ActivitySummaryRepo.timeout = const Duration(milliseconds: 50);
    addTearDown(
      () => ActivitySummaryRepo.timeout = const Duration(seconds: 60),
    );
    final never = Completer<http.Response>();

    final (controller, requests) = await open(
      room,
      respond: (_) => throw StateError('unused'),
      pending: never.future,
    );

    final own = controller.summaryView.value.cardFor(userId)!;
    expect(requests, hasLength(1));
    expect(own.isLoading, isFalse);
    expect(own.hasFailed, isFalse);
    expect(own.participant?.feedback, 'Bien joué.');
  });

  test('a plan that fails to map shows the card as written', () async {
    final room = finishedRoom(langCode: 'fr', requestHash: 'row-bad-plan');
    // A session room with no plan in state, so the controller fetches one.
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': '${PangeaRoomTypes.activitySession}:bad-plan'},
        senderId: userId,
        eventId: '\$create',
        originServerTs: DateTime.now(),
        stateKey: '',
        room: room,
      ),
    );
    final requests = <String>[];
    late ActivityChatController controller;
    await http.runWithClient(
      () async {
        controller = ActivityChatController(
          userID: userId,
          room: room,
          inputFocus: FocusNode(),
        );
        for (
          var i = 0;
          i < 100 && controller.summaryView.value.isLoading;
          i++
        ) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      },
      // The plan fetch succeeds with a body that has no plan in it.
      () => MockClient((request) async {
        requests.add(request.url.path);
        return http.Response('{}', 200, request: request);
      }),
    );
    addTearDown(controller.dispose);

    final own = controller.summaryView.value.cardFor(userId)!;
    expect(requests, isNot(contains(summaryPath)));
    expect(own.isLoading, isFalse);
    expect(own.participant?.feedback, 'Bien joué.');
  });

  test('a card already in the viewer\'s language is not translated', () async {
    // With a plan, a wrongful translation would reach choreo.
    final room = finishedRoom(
      langCode: 'en-US',
      requestHash: 'row-same',
      withPlan: true,
    );

    final (controller, requests) = await open(room, respond: translated);

    expect(requests, isEmpty);
    expect(ownFeedback(controller), 'Bien joué.');
  });

  test(
    'a bot card without a row id is shown as written, and reported',
    () async {
      ErrorHandler.resetReportedOnceKeysForTest();
      final room = finishedRoom(langCode: 'fr');

      final (controller, requests) = await open(room, respond: translated);

      expect(requests, isEmpty);
      expect(ownFeedback(controller), 'Bien joué.');
      expect(
        ErrorHandler.reportedOnceKeysForTest,
        contains('activity_summary_no_request_hash'),
      );
    },
  );

  group('confetti', () {
    var liveCount = 0;
    void writeSlot(
      Room room,
      String stateKey,
      Map<String, dynamic> content, {
      String sender = bot,
    }) => room.setState(
      Event(
        type: PangeaEventTypes.activitySummary,
        stateKey: stateKey,
        content: content,
        senderId: sender,
        eventId: '\$live-${liveCount++}',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );

    test('the learner\'s card landing while the room is open fires once it '
        'shows, translated', () async {
      final room = finishedRoom(
        langCode: 'fr',
        requestHash: 'row-old',
        withPlan: true,
      );
      final (controller, _) = await open(room, respond: translated);
      expect(controller.confettiNotifier.value, isFalse);

      await http.runWithClient(() async {
        // The bot regenerates: a loading marker, then a new card.
        writeSlot(
          room,
          ActivitySummaryStateKeys.card(userId),
          ActivitySummaryModel(
            requestedAt: DateTime.now(),
            langCode: 'fr',
          ).toJson(),
        );
        await Future.delayed(Duration.zero);
        expect(controller.confettiNotifier.value, isFalse);

        writeSlot(
          room,
          ActivitySummaryStateKeys.card(userId),
          ActivitySummaryModel(
            summary: card(userId, 'Encore mieux.'),
            langCode: 'fr',
            requestHash: 'row-new',
          ).toJson(),
        );
        for (var i = 0; i < 100 && !controller.confettiNotifier.value; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }, () => MockClient((request) async => translated(request)));

      expect(ownFeedback(controller), 'Well played.');
      expect(controller.confettiNotifier.value, isTrue);
    });

    test('ending again shows loading until the card for the new finish, '
        'which fires it', () async {
      final room = finishedRoom(langCode: 'en', requestHash: 'row-first');
      final (controller, _) = await open(room, respond: translated);
      expect(ownFeedback(controller), 'Bien joué.');

      void setOwnRole(DateTime? finishedAt) => room.setState(
        Event(
          type: PangeaEventTypes.activityRole,
          stateKey: '',
          content: ActivityRolesModel({
            'role1': ActivityRoleModel(
              id: 'role1',
              userId: userId,
              role: 'Customer',
              finishedAt: finishedAt,
            ),
          }).toJson(),
          senderId: userId,
          eventId: '\$roles-${liveCount++}',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );

      // Resumed play, then ended again.
      setOwnRole(null);
      await Future.delayed(Duration.zero);
      expect(controller.summaryView.value.cards, isEmpty);
      final again = DateTime.utc(2026, 1, 1, 1);
      setOwnRole(again);
      await Future.delayed(Duration.zero);
      expect(controller.summaryView.value.cardFor(userId)?.isLoading, isTrue);

      writeSlot(
        room,
        ActivitySummaryStateKeys.card(userId),
        ActivitySummaryModel(
          summary: card(userId, 'Encore mieux.'),
          langCode: 'en',
          requestHash: 'row-again',
          finishedAt: again,
        ).toJson(),
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(ownFeedback(controller), 'Encore mieux.');
      expect(controller.confettiNotifier.value, isTrue);
    });

    test('a coursemate\'s card landing does not fire it', () async {
      final room = finishedRoom(
        langCode: 'en',
        requestHash: 'row-own',
        withCoursemate: true,
      );
      final (controller, _) = await open(room, respond: translated);

      writeSlot(
        room,
        ActivitySummaryStateKeys.card(coursemate),
        ActivitySummaryModel(
          summary: card(coursemate, 'Theirs.'),
          langCode: 'en',
          requestHash: 'row-theirs',
        ).toJson(),
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(
        controller.summaryView.value.cardFor(coursemate)?.participant?.feedback,
        'Theirs.',
      );
      expect(controller.confettiNotifier.value, isFalse);
    });

    test(
      'a regeneration that fails keeps the old card without confetti',
      () async {
        final room = finishedRoom(langCode: 'en', requestHash: 'row-keep');
        final (controller, _) = await open(room, respond: translated);

        // The bot regenerates: a loading marker, then an error marker that
        // still carries the card the learner had.
        writeSlot(
          room,
          ActivitySummaryStateKeys.card(userId),
          ActivitySummaryModel(
            requestedAt: DateTime.now(),
            langCode: 'en',
          ).toJson(),
        );
        await Future.delayed(Duration.zero);
        writeSlot(
          room,
          ActivitySummaryStateKeys.card(userId),
          ActivitySummaryModel(
            summary: card(userId, 'Bien joué.'),
            errorAt: DateTime.now(),
            langCode: 'en',
            requestHash: 'row-keep',
          ).toJson(),
        );
        await Future.delayed(const Duration(milliseconds: 20));

        expect(
          controller.summaryView.value.cardFor(userId)?.updateFailed,
          isTrue,
        );
        expect(controller.confettiNotifier.value, isFalse);
      },
    );

    test('reopening a summarized room, or the analytics slot\'s write, does '
        'not fire it', () async {
      final room = finishedRoom(langCode: 'en', requestHash: 'row-reopen');
      final (controller, _) = await open(room, respond: translated);
      expect(ownFeedback(controller), isNotNull);

      writeSlot(
        room,
        ActivitySummaryStateKeys.learnerAnalytics(userId),
        ActivitySummaryAnalyticsModel().toJson(),
        sender: userId,
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(ownFeedback(controller), isNotNull);
      expect(controller.confettiNotifier.value, isFalse);
    });
  });
}
