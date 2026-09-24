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
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_activity_chat_pangea_controller.dart';
import 'get_test_client.dart';

/// The bot writes the summary in the activity's language of instruction. A
/// viewer whose first language differs sees it translated: the loading state
/// stays up while the translation is fetched, and a failed translation leaves
/// the summary as written (#9199; client activities.instructions.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:example.org';
  const userId = '@test:fakeServer.notExisting';
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

  ActivitySummaryResponseModel summaryText(String text) =>
      ActivitySummaryResponseModel(participants: const [], summary: text);

  /// A finished activity whose bot summary is in [langCode], stored under
  /// choreo row [requestHash]. A translation is built against the activity's
  /// plan, so only [withPlan] rooms can fetch one.
  Room finishedRoom({
    required String langCode,
    String? requestHash,
    bool withPlan = false,
  }) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    var count = 0;
    void setState(
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
        eventId: '\$state${count++}',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );

    if (withPlan) {
      setState(
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
    final role = ActivityRoleModel(
      id: 'role1',
      userId: userId,
      role: 'Customer',
      finishedAt: DateTime.utc(2026),
    );
    setState(
      PangeaEventTypes.activityRole,
      '',
      ActivityRolesModel({role.id: role}).toJson(),
    );
    setState(EventTypes.RoomMember, userId, {'membership': 'join'});
    setState(EventTypes.RoomMember, bot, {'membership': 'join'}, sender: bot);
    setState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.canonical,
      ActivitySummaryModel(
        summary: summaryText('Bien joué.'),
        langCode: langCode,
        requestHash: requestHash,
      ).toJson(),
      sender: bot,
    );
    // Already written, so the controller has no analytics to compute.
    setState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.analytics,
      ActivitySummaryAnalyticsModel().toJson(),
    );
    return room;
  }

  /// Opens the room with choreo answered by [respond], and returns the
  /// controller once any translation has settled, plus the requests made.
  Future<(ActivityChatController, List<Map<String, dynamic>>)> open(
    Room room, {
    required http.Response Function(http.Request request) respond,
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
        return respond(request);
      }),
    );
    addTearDown(controller.dispose);
    return (controller, requests);
  }

  http.Response translated(http.Request request) => http.Response(
    jsonEncode(summaryText('Well played.').toJson()),
    200,
    request: request,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test('translates the bot\'s summary into the viewer\'s L1', () async {
    final room = finishedRoom(
      langCode: 'fr',
      requestHash: 'row-translate',
      withPlan: true,
    );

    final (controller, requests) = await open(room, respond: translated);

    expect(controller.summaryView.value.summary?.summary, 'Well played.');
    expect(requests, hasLength(1));
    expect(requests.single['source_request_hash'], 'row-translate');
    expect(requests.single['viewer_l1'], 'en');
    expect(
      (requests.single['activity'] as Map)['activity_id'] ??
          (requests.single['activity'] as Map)['activityId'],
      isNotNull,
    );
  });

  test('keeps the loading state up while the translation is fetched', () {
    final room = finishedRoom(langCode: 'fr', requestHash: 'row-pending');
    MatrixState.pangeaController = ActivityChatTestPangeaController(
      accessToken: 'syt_test_token',
    );
    final controller = ActivityChatController(
      userID: userId,
      room: room,
      inputFocus: FocusNode(),
    );
    addTearDown(controller.dispose);

    // Nothing has answered yet: the viewer sees loading, not the French text.
    expect(controller.summaryView.value.isLoading, isTrue);
    expect(controller.summaryView.value.summary, isNull);
  });

  test('a failed translation shows the summary as written', () async {
    final room = finishedRoom(
      langCode: 'fr',
      requestHash: 'row-fails',
      withPlan: true,
    );

    final (controller, requests) = await open(
      room,
      respond: (request) => http.Response('', 500, request: request),
    );

    final view = controller.summaryView.value;
    expect(requests, hasLength(1));
    expect(view.isLoading, isFalse);
    expect(view.hasFailed, isFalse);
    expect(view.summary?.summary, 'Bien joué.');
  });

  test(
    'a summary already in the viewer\'s language is not translated',
    () async {
      // With a plan, a wrongful translation would reach choreo.
      final room = finishedRoom(
        langCode: 'en-US',
        requestHash: 'row-same',
        withPlan: true,
      );

      final (controller, requests) = await open(room, respond: translated);

      expect(requests, isEmpty);
      expect(controller.summaryView.value.summary?.summary, 'Bien joué.');
    },
  );

  test(
    'a bot summary without a row id is shown as written, and reported',
    () async {
      ErrorHandler.resetReportedOnceKeysForTest();
      final room = finishedRoom(langCode: 'fr');

      final (controller, requests) = await open(room, respond: translated);

      expect(requests, isEmpty);
      expect(controller.summaryView.value.summary?.summary, 'Bien joué.');
      expect(
        ErrorHandler.reportedOnceKeysForTest,
        contains('activity_summary_no_request_hash'),
      );
    },
  );

  group('confetti', () {
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
        eventId: '\$live-$stateKey',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );

    test('a summary that lands while the room is open fires once it shows, '
        'translated', () async {
      final room = finishedRoom(
        langCode: 'fr',
        requestHash: 'row-old',
        withPlan: true,
      );
      final (controller, _) = await open(room, respond: translated);
      expect(controller.confettiNotifier.value, isFalse);

      await http.runWithClient(() async {
        // The bot regenerates: a loading marker, then a new summary.
        writeSlot(
          room,
          ActivitySummaryStateKeys.canonical,
          ActivitySummaryModel(
            requestedAt: DateTime.now(),
            langCode: 'fr',
          ).toJson(),
        );
        await Future.delayed(Duration.zero);
        expect(controller.confettiNotifier.value, isFalse);

        writeSlot(
          room,
          ActivitySummaryStateKeys.canonical,
          ActivitySummaryModel(
            summary: summaryText('Encore mieux.'),
            langCode: 'fr',
            requestHash: 'row-new',
          ).toJson(),
        );
        for (var i = 0; i < 100 && !controller.confettiNotifier.value; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }, () => MockClient((request) async => translated(request)));

      expect(controller.summaryView.value.summary?.summary, 'Well played.');
      expect(controller.confettiNotifier.value, isTrue);
    });

    test('reopening a summarized room, or the analytics slot\'s write, does '
        'not fire it', () async {
      final room = finishedRoom(langCode: 'en', requestHash: 'row-reopen');
      final (controller, _) = await open(room, respond: translated);
      expect(controller.summaryView.value.summary, isNotNull);

      writeSlot(
        room,
        ActivitySummaryStateKeys.analytics,
        ActivitySummaryAnalyticsModel().toJson(),
        sender: userId,
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(controller.summaryView.value.summary, isNotNull);
      expect(controller.confettiNotifier.value, isFalse);
    });
  });
}
