import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// The client shows the summary the bot writes to the `canonical` slot and
/// asks for retries and regenerations through the `request` slot (#9199; org
/// doc activity-summary.instructions.md, "Coordination model").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:example.org';
  const learner = '@test:fakeServer.notExisting';
  const coursemate = '@alice:example.org';
  const roomId = '!summary:fakeServer.notExisting';

  late Client client;
  var eventCount = 0;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=$bot');
    MatrixState.pangeaController = FakePangeaController(userL1Code: 'en');
    // The bot's name is read through a GetStorage box, which needs
    // path_provider; point it at a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('summary_view');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async => client = await getTestClient());
  tearDown(() => client.dispose());

  void setState(
    Room room,
    String type,
    String stateKey,
    Map<String, dynamic> content, {
    required String sender,
    required DateTime at,
  }) => room.setState(
    Event(
      type: type,
      stateKey: stateKey,
      content: content,
      senderId: sender,
      eventId: '\$event${eventCount++}',
      originServerTs: at,
      room: room,
    ),
  );

  void setMembership(Room room, String userId, Membership membership) =>
      setState(
        room,
        EventTypes.RoomMember,
        userId,
        {'membership': membership.name},
        sender: userId,
        at: DateTime.utc(2026),
      );

  /// A finished activity with the bot and the learner in the room.
  Room finishedRoom({bool botJoined = true}) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    final role = ActivityRoleModel(
      id: 'role1',
      userId: learner,
      role: 'Customer',
      finishedAt: DateTime.utc(2026),
    );
    setState(
      room,
      PangeaEventTypes.activityRole,
      '',
      ActivityRolesModel({role.id: role}).toJson(),
      sender: learner,
      at: DateTime.utc(2026),
    );
    setMembership(room, learner, Membership.join);
    setMembership(room, bot, botJoined ? Membership.join : Membership.leave);
    return room;
  }

  ActivitySummaryResponseModel summaryText(String text) =>
      ActivitySummaryResponseModel(participants: const [], summary: text);

  void setSummary(
    Room room,
    ActivitySummaryModel model, {
    String stateKey = ActivitySummaryStateKeys.canonical,
    String sender = bot,
    DateTime? at,
  }) => setState(
    room,
    PangeaEventTypes.activitySummary,
    stateKey,
    model.toJson(),
    sender: sender,
    at: at ?? DateTime.now(),
  );

  void setRequest(Room room, {required DateTime at}) => setState(
    room,
    PangeaEventTypes.activitySummary,
    ActivitySummaryStateKeys.request,
    {'requested_at': at.toIso8601String()},
    sender: learner,
    at: at,
  );

  ActivitySummaryView view(Room room, {DateTime? waitingSince}) =>
      room.activitySummaryView(waitingSince: waitingSince);

  test('shows the bot\'s summary, and offers feedback', () {
    final room = finishedRoom();
    setSummary(room, ActivitySummaryModel(summary: summaryText('Well done.')));

    final shown = view(room);
    expect(shown.summary?.summary, 'Well done.');
    expect(shown.isLoading, isFalse);
    expect(shown.hasFailed, isFalse);
    expect(shown.updateFailed, isFalse);
    expect(shown.canRequest, isTrue);
  });

  test('ignores a canonical summary anyone but the bot wrote', () {
    final room = finishedRoom();
    setSummary(
      room,
      ActivitySummaryModel(summary: summaryText('Forged.')),
      sender: coursemate,
    );

    expect(room.activitySummary, isNull);
    expect(view(room).summary, isNull);
  });

  test('waits for the bot after the finish, then fails', () {
    final room = finishedRoom();

    final waiting = view(room, waitingSince: DateTime.now());
    expect(waiting.isLoading, isTrue);
    expect(waiting.loadingDeadline, isNotNull);

    final gaveUp = view(
      room,
      waitingSince: DateTime.now().subtract(
        ActivitySummaryModel.requestTimeout + const Duration(seconds: 1),
      ),
    );
    expect(gaveUp.isLoading, isFalse);
    expect(gaveUp.hasFailed, isTrue);
    expect(gaveUp.canRequest, isTrue);
  });

  test('offers no retry when a bot that never wrote has left', () {
    // Members load lazily, so the wait never depends on the bot's membership.
    final room = finishedRoom(botJoined: false);
    expect(view(room, waitingSince: DateTime.now()).isLoading, isTrue);

    final shown = view(
      room,
      waitingSince: DateTime.now().subtract(
        ActivitySummaryModel.requestTimeout + const Duration(seconds: 1),
      ),
    );
    expect(shown.hasFailed, isTrue);
    expect(shown.canRequest, isFalse);
  });

  test('shows loading while the bot\'s call runs, until it times out', () {
    final room = finishedRoom();
    final requestedAt = DateTime.now();
    setSummary(room, ActivitySummaryModel(requestedAt: requestedAt));

    final loading = view(room);
    expect(loading.isLoading, isTrue);
    expect(
      loading.loadingDeadline,
      requestedAt.add(ActivitySummaryModel.requestTimeout),
    );

    setSummary(
      room,
      ActivitySummaryModel(
        requestedAt: DateTime.now().subtract(
          ActivitySummaryModel.requestTimeout + const Duration(seconds: 1),
        ),
      ),
    );
    expect(view(room).hasFailed, isTrue);
  });

  test('shows loading, not the old summary, while it regenerates', () {
    final room = finishedRoom();
    setSummary(
      room,
      ActivitySummaryModel(
        summary: summaryText('First try.'),
        requestedAt: DateTime.now(),
      ),
    );

    final shown = view(room);
    expect(shown.isLoading, isTrue);
    expect(shown.summary, isNull);
  });

  test('keeps the old summary, with a note, when a regeneration fails', () {
    final room = finishedRoom();
    setSummary(
      room,
      ActivitySummaryModel(
        summary: summaryText('First try.'),
        errorAt: DateTime.now(),
      ),
    );

    final shown = view(room);
    expect(shown.summary?.summary, 'First try.');
    expect(shown.updateFailed, isTrue);
    expect(shown.hasFailed, isFalse);
  });

  test('a bot error with no summary fails and offers a retry', () {
    final room = finishedRoom();
    setSummary(room, ActivitySummaryModel(errorAt: DateTime.now()));

    final shown = view(room);
    expect(shown.hasFailed, isTrue);
    expect(shown.canRequest, isTrue);
  });

  test('a request the bot has not picked up yet shows loading', () {
    final room = finishedRoom();
    final summaryAt = DateTime.now().subtract(const Duration(minutes: 5));
    setSummary(
      room,
      ActivitySummaryModel(
        summary: summaryText('First try.'),
        callStartedTs: summaryAt.millisecondsSinceEpoch,
      ),
      at: summaryAt,
    );
    final requestAt = DateTime.now();
    setRequest(room, at: requestAt);

    final shown = view(room);
    expect(shown.isLoading, isTrue);
    expect(
      shown.loadingDeadline,
      requestAt.add(ActivitySummaryModel.requestTimeout),
    );
  });

  test('a request the bot already served does not', () {
    final room = finishedRoom();
    final requestAt = DateTime.now().subtract(const Duration(seconds: 30));
    setRequest(room, at: requestAt);
    // The call behind this summary started after the request was written.
    setSummary(
      room,
      ActivitySummaryModel(
        summary: summaryText('Second try.'),
        callStartedTs: requestAt
            .add(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
      ),
    );

    final shown = view(room);
    expect(shown.isLoading, isFalse);
    expect(shown.summary?.summary, 'Second try.');
  });

  test('offers no feedback once the bot\'s service window has passed', () {
    final room = finishedRoom();
    setSummary(
      room,
      ActivitySummaryModel(summary: summaryText('Old.')),
      at: DateTime.now().subtract(
        activitySummaryServiceWindow + const Duration(minutes: 1),
      ),
    );

    final shown = view(room);
    expect(shown.summary?.summary, 'Old.');
    expect(shown.canRequest, isFalse);
  });

  test('falls back to a summary an older client wrote', () {
    final room = finishedRoom();
    setSummary(
      room,
      ActivitySummaryModel(summary: summaryText('Unkeyed.')),
      stateKey: ActivitySummaryStateKeys.legacy,
      sender: coursemate,
    );
    expect(view(room).summary?.summary, 'Unkeyed.');

    setSummary(
      room,
      ActivitySummaryModel(summary: summaryText('Per L1.')),
      stateKey: 'en',
      sender: coursemate,
    );
    expect(view(room).summary?.summary, 'Per L1.');
    // Feedback would reach the bot with no summary of its own to regenerate.
    expect(view(room).canRequest, isFalse);

    setSummary(room, ActivitySummaryModel(summary: summaryText('The bot\'s.')));
    expect(view(room).summary?.summary, 'The bot\'s.');
  });

  test('reads analytics from their own slot, else from an old summary', () {
    final room = finishedRoom();
    Map<String, dynamic> uses(String lemma) => {
      learner: [
        {'lemma': lemma, 'type': 'vocab', 'cat': 'n', 'times_used': 1},
      ],
    };
    setSummary(
      room,
      ActivitySummaryModel.fromJson({'analytics': uses('café')}),
      stateKey: 'en',
      sender: coursemate,
    );
    expect(
      room
          .activitySummaryAnalytics
          ?.constructs[learner]
          ?.usages
          .values
          .single
          .identifier
          .lemma,
      'café',
    );

    setState(
      room,
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.analytics,
      uses('leche'),
      sender: coursemate,
      at: DateTime.now(),
    );
    expect(
      room
          .activitySummaryAnalytics
          ?.constructs[learner]
          ?.usages
          .values
          .single
          .identifier
          .lemma,
      'leche',
    );
  });

  test('shows nothing before the activity is finished', () {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    setSummary(room, ActivitySummaryModel(summary: summaryText('Early.')));

    final shown = view(room, waitingSince: DateTime.now());
    expect(shown.summary, isNull);
    expect(shown.isLoading, isFalse);
    expect(shown.hasFailed, isFalse);
  });
}
