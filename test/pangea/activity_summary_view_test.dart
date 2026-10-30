import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// Each learner gets their own card, made by the bot into `card:<learner>`
/// when they finish; rooms from before per-learner cards still render from
/// the `canonical` slot or an older client's (#795; org doc
/// activity-summary.instructions.md, "Room state").
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

  Event setState(
    Room room,
    String type,
    String stateKey,
    Map<String, dynamic> content, {
    required String sender,
    required DateTime at,
  }) {
    final event = Event(
      type: type,
      stateKey: stateKey,
      content: content,
      senderId: sender,
      eventId: '\$event${eventCount++}',
      originServerTs: at,
      room: room,
    );
    room.setState(event);
    return event;
  }

  void setMembership(Room room, String userId, Membership membership) =>
      setState(
        room,
        EventTypes.RoomMember,
        userId,
        {'membership': membership.name},
        sender: userId,
        at: DateTime.utc(2026),
      );

  /// Writes the room's roles: who has finished, the learner at
  /// [learnerFinishedAt], and when the event was sent, at [at].
  void setRoles(
    Room room, {
    required bool learnerDone,
    required bool coursemateDone,
    DateTime? learnerFinishedAt,
    DateTime? at,
  }) {
    final roles = {
      'role1': ActivityRoleModel(
        id: 'role1',
        userId: learner,
        role: 'Customer',
        finishedAt: learnerDone
            ? learnerFinishedAt ?? DateTime.utc(2026)
            : null,
      ),
      'role2': ActivityRoleModel(
        id: 'role2',
        userId: coursemate,
        role: 'Barista',
        finishedAt: coursemateDone ? DateTime.utc(2026) : null,
      ),
    };
    setState(
      room,
      PangeaEventTypes.activityRole,
      '',
      ActivityRolesModel(roles).toJson(),
      sender: learner,
      at: at ?? DateTime.utc(2026),
    );
  }

  /// A two-learner activity with the bot in the room.
  Room activityRoom({
    bool learnerDone = true,
    bool coursemateDone = false,
    bool botJoined = true,
  }) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    setRoles(room, learnerDone: learnerDone, coursemateDone: coursemateDone);
    setMembership(room, learner, Membership.join);
    setMembership(room, coursemate, Membership.join);
    setMembership(room, bot, botJoined ? Membership.join : Membership.leave);
    return room;
  }

  ParticipantSummaryModel feedback(String userId, String text) =>
      ParticipantSummaryModel(
        participantId: userId,
        feedback: text,
        cefrLevel: 'A2',
        superlatives: const [],
      );

  /// One learner's card content, as the bot writes it.
  ActivitySummaryResponseModel card(String userId, String text) =>
      ActivitySummaryResponseModel(
        participants: [feedback(userId, text)],
        summary: '',
      );

  /// A whole-room summary, as the bot or an older client wrote it before
  /// per-learner cards.
  ActivitySummaryResponseModel roomSummary(
    String text, {
    List<String> participants = const [learner, coursemate],
  }) => ActivitySummaryResponseModel(
    participants: [for (final p in participants) feedback(p, '$text ($p)')],
    summary: text,
  );

  Event setSlot(
    Room room,
    String stateKey,
    ActivitySummaryModel model, {
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

  Event setCard(
    Room room,
    String userId,
    ActivitySummaryModel model, {
    String sender = bot,
    DateTime? at,
  }) => setSlot(
    room,
    ActivitySummaryStateKeys.card(userId),
    model,
    sender: sender,
    at: at,
  );

  void setRequest(
    Room room, {
    required DateTime at,
    String? userId,
    String sender = learner,
  }) => setState(
    room,
    PangeaEventTypes.activitySummary,
    ActivitySummaryStateKeys.request,
    {'user_id': ?userId, 'requested_at': at.toIso8601String()},
    sender: sender,
    at: at,
  );

  ActivitySummaryView view(
    Room room, {
    Map<String, ActivitySummaryWait> waits = const {},
  }) => room.activitySummaryView(waits: waits);

  final expired =
      ActivitySummaryModel.requestTimeout + const Duration(seconds: 1);

  /// When the fixtures' learners finished.
  final finish = DateTime.utc(2026);

  group('own card, others still playing', () {
    test('shows the learner their own card as soon as the bot writes it', () {
      final room = activityRoom();
      setCard(
        room,
        learner,
        ActivitySummaryModel(summary: card(learner, 'Mine.')),
      );

      final shown = view(room);
      expect(shown.cards.map((c) => c.userId), [learner]);
      final own = shown.cardFor(learner)!;
      expect(own.participant?.feedback, 'Mine.');
      expect(own.isLoading, isFalse);
      expect(own.hasFailed, isFalse);
      expect(own.updateFailed, isFalse);
      // The activity is still running, so the bot is there to answer.
      expect(own.canRequest, isTrue);
      expect(shown.groupSummary, isNull);
    });

    test('shows nothing to a learner who is still playing', () {
      final room = activityRoom(learnerDone: false, coursemateDone: true);
      setCard(
        room,
        coursemate,
        ActivitySummaryModel(summary: card(coursemate, 'Theirs.')),
      );

      expect(view(room).cards, isEmpty);
    });

    test('waits for the bot after the finish, then fails with a retry', () {
      final room = activityRoom();

      final waiting = view(
        room,
        waits: {
          learner: ActivitySummaryWait(
            since: DateTime.now(),
            finishedAt: finish,
          ),
        },
      ).cardFor(learner)!;
      expect(waiting.isLoading, isTrue);
      expect(waiting.loadingDeadline, isNotNull);

      final gaveUp = view(
        room,
        waits: {
          learner: ActivitySummaryWait(
            since: DateTime.now().subtract(expired),
            finishedAt: finish,
          ),
        },
      ).cardFor(learner)!;
      expect(gaveUp.isLoading, isFalse);
      expect(gaveUp.hasFailed, isTrue);
      expect(gaveUp.canRequest, isTrue);
    });

    test('shows loading while the bot\'s call runs, until it times out', () {
      final room = activityRoom();
      final requestedAt = DateTime.now();
      setCard(room, learner, ActivitySummaryModel(requestedAt: requestedAt));

      final loading = view(room).cardFor(learner)!;
      expect(loading.isLoading, isTrue);
      expect(
        loading.loadingDeadline,
        requestedAt.add(ActivitySummaryModel.requestTimeout),
      );

      setCard(
        room,
        learner,
        ActivitySummaryModel(requestedAt: DateTime.now().subtract(expired)),
      );
      expect(view(room).cardFor(learner)!.hasFailed, isTrue);
    });

    test('a bot error with no card fails and offers a retry', () {
      final room = activityRoom();
      setCard(room, learner, ActivitySummaryModel(errorAt: DateTime.now()));

      final own = view(room).cardFor(learner)!;
      expect(own.hasFailed, isTrue);
      expect(own.canRequest, isTrue);
    });

    test('keeps the old card, with a note, when a regeneration fails', () {
      final room = activityRoom();
      setCard(
        room,
        learner,
        ActivitySummaryModel(
          summary: card(learner, 'First try.'),
          errorAt: DateTime.now(),
        ),
      );

      final own = view(room).cardFor(learner)!;
      expect(own.participant?.feedback, 'First try.');
      expect(own.updateFailed, isTrue);
      expect(own.hasFailed, isFalse);
    });

    test('ignores a card anyone but the bot wrote, and reports it', () {
      ErrorHandler.resetReportedOnceKeysForTest();
      final room = activityRoom();
      setCard(
        room,
        learner,
        ActivitySummaryModel(summary: card(learner, 'Forged.')),
        sender: coursemate,
      );

      final own = view(room).cardFor(learner)!;
      expect(own.participant, isNull);
      expect(own.hasFailed, isTrue);
      expect(
        ErrorHandler.reportedOnceKeysForTest,
        contains('activity_summary_foreign_slot:$roomId:card:$learner'),
      );
    });

    test('carries the card\'s language and row id for translation', () {
      final room = activityRoom();
      setCard(
        room,
        learner,
        ActivitySummaryModel(
          summary: card(learner, 'Bien joué.'),
          langCode: 'fr',
          requestHash: 'row-learner',
        ),
      );

      final own = view(room).cardFor(learner)!;
      expect(own.langCode, 'fr');
      expect(own.requestHash, 'row-learner');
      expect(own.needsTranslation('en'), isTrue);
      expect(own.needsTranslation('fr'), isFalse);
    });

    test('the goal header stays until the whole activity has finished', () {
      final room = activityRoom();
      setCard(
        room,
        learner,
        ActivitySummaryModel(summary: card(learner, 'Mine.')),
      );
      expect(room.hasGeneratedActivitySummary, isFalse);

      setRoles(room, learnerDone: true, coursemateDone: true);
      expect(room.hasGeneratedActivitySummary, isTrue);
    });
  });

  group('others\' cards', () {
    test('a coursemate\'s card joins once they finish, in role order', () {
      final room = activityRoom(coursemateDone: true);
      setCard(
        room,
        coursemate,
        ActivitySummaryModel(summary: card(coursemate, 'Theirs.')),
      );
      setCard(
        room,
        learner,
        ActivitySummaryModel(summary: card(learner, 'Mine.')),
      );

      final shown = view(room);
      expect(shown.cards.map((c) => c.userId), [learner, coursemate]);
      expect(shown.cardFor(coursemate)?.participant?.feedback, 'Theirs.');
    });

    test('a card from before the coursemate resumed play stays hidden', () {
      final room = activityRoom();
      setCard(
        room,
        coursemate,
        ActivitySummaryModel(summary: card(coursemate, 'Stale.')),
      );

      expect(view(room).cardFor(coursemate), isNull);
    });

    test('a request for one learner\'s card leaves the others alone', () {
      final room = activityRoom(coursemateDone: true);
      final cardAt = DateTime.now().subtract(const Duration(minutes: 5));
      for (final userId in [learner, coursemate]) {
        setCard(
          room,
          userId,
          ActivitySummaryModel(
            summary: card(userId, 'First try.'),
            callStartedTs: cardAt.millisecondsSinceEpoch,
          ),
          at: cardAt,
        );
      }
      final requestAt = DateTime.now();
      setRequest(room, at: requestAt, userId: coursemate);

      final shown = view(room);
      expect(shown.cardFor(learner)!.isLoading, isFalse);
      expect(shown.cardFor(learner)!.participant?.feedback, 'First try.');
      final theirs = shown.cardFor(coursemate)!;
      expect(theirs.isLoading, isTrue);
      expect(
        theirs.loadingDeadline,
        requestAt.add(ActivitySummaryModel.requestTimeout),
      );
    });

    test('a request that names nobody is for its sender\'s own card', () {
      final room = activityRoom(coursemateDone: true);
      final cardAt = DateTime.now().subtract(const Duration(minutes: 5));
      for (final userId in [learner, coursemate]) {
        setCard(
          room,
          userId,
          ActivitySummaryModel(
            summary: card(userId, 'First try.'),
            callStartedTs: cardAt.millisecondsSinceEpoch,
          ),
          at: cardAt,
        );
      }
      setRequest(room, at: DateTime.now(), sender: coursemate);

      final shown = view(room);
      expect(shown.cardFor(learner)!.isLoading, isFalse);
      expect(shown.cardFor(coursemate)!.isLoading, isTrue);
    });

    test('a request the bot already served does not show loading', () {
      final room = activityRoom();
      final requestAt = DateTime.now().subtract(const Duration(seconds: 30));
      setRequest(room, at: requestAt, userId: learner);
      setCard(
        room,
        learner,
        ActivitySummaryModel(
          summary: card(learner, 'Second try.'),
          callStartedTs: requestAt
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        ),
      );

      final own = view(room).cardFor(learner)!;
      expect(own.isLoading, isFalse);
      expect(own.participant?.feedback, 'Second try.');
    });
  });

  group('ending again', () {
    final later = DateTime.utc(2026, 1, 1, 0, 10);

    test('a card made for an earlier finish shows loading until the new one, '
        'then itself with a note', () {
      final room = activityRoom();
      setRoles(
        room,
        learnerDone: true,
        coursemateDone: false,
        learnerFinishedAt: later,
      );
      setCard(
        room,
        learner,
        ActivitySummaryModel(
          summary: card(learner, 'Before.'),
          finishedAt: finish,
        ),
      );

      final waiting = view(
        room,
        waits: {
          learner: ActivitySummaryWait(
            since: DateTime.now(),
            finishedAt: later,
          ),
        },
      ).cardFor(learner)!;
      expect(waiting.isLoading, isTrue);
      expect(waiting.participant, isNull);

      final gaveUp = view(
        room,
        waits: {
          learner: ActivitySummaryWait(
            since: DateTime.now().subtract(expired),
            finishedAt: later,
          ),
        },
      ).cardFor(learner)!;
      expect(gaveUp.participant?.feedback, 'Before.');
      expect(gaveUp.updateFailed, isTrue);

      // A wait left over from the earlier finish says nothing about this one.
      final leftOver = view(
        room,
        waits: {
          learner: ActivitySummaryWait(
            since: DateTime.now(),
            finishedAt: finish,
          ),
        },
      ).cardFor(learner)!;
      expect(leftOver.isLoading, isFalse);
      expect(leftOver.updateFailed, isTrue);

      // The card made for this finish ends the wait.
      setCard(
        room,
        learner,
        ActivitySummaryModel(
          summary: card(learner, 'After.'),
          finishedAt: later,
        ),
      );
      final replaced = view(
        room,
        waits: {
          learner: ActivitySummaryWait(
            since: DateTime.now(),
            finishedAt: later,
          ),
        },
      ).cardFor(learner)!;
      expect(replaced.isLoading, isFalse);
      expect(replaced.updateFailed, isFalse);
      expect(replaced.participant?.feedback, 'After.');
    });

    test('a card made for this finish is current however its time is '
        'written', () {
      final room = activityRoom();
      setState(
        room,
        PangeaEventTypes.activitySummary,
        ActivitySummaryStateKeys.card(learner),
        {
          ...ActivitySummaryModel(summary: card(learner, 'Mine.')).toJson(),
          'finished_at': '2026-01-01T00:00:00+00:00',
        },
        sender: bot,
        at: DateTime.now(),
      );

      expect(room.hasActivitySummaryCardFor(learner), isTrue);
      final own = view(room).cardFor(learner)!;
      expect(own.participant?.feedback, 'Mine.');
      expect(own.updateFailed, isFalse);

      setRoles(
        room,
        learnerDone: true,
        coursemateDone: false,
        learnerFinishedAt: later,
      );
      expect(room.hasActivitySummaryCardFor(learner), isFalse);
    });
  });

  group('whole activity finished', () {
    test('cards win over the canonical copy, which has no group text', () {
      final room = activityRoom(coursemateDone: true);
      setCard(
        room,
        learner,
        ActivitySummaryModel(summary: card(learner, 'Mine.')),
      );
      setCard(
        room,
        coursemate,
        ActivitySummaryModel(summary: card(coursemate, 'Theirs.')),
      );
      setSlot(
        room,
        ActivitySummaryStateKeys.canonical,
        ActivitySummaryModel(
          summary: ActivitySummaryResponseModel(
            participants: [
              feedback(learner, 'Copied.'),
              feedback(coursemate, 'Copied.'),
            ],
            summary: '',
          ),
        ),
      );

      final shown = view(room);
      expect(shown.cardFor(learner)?.participant?.feedback, 'Mine.');
      expect(shown.cardFor(coursemate)?.participant?.feedback, 'Theirs.');
      expect(shown.groupSummary, isNull);
    });

    test('an observer with no role sees every card', () {
      final room = activityRoom(learnerDone: true, coursemateDone: true);
      // Re-seat the viewer's role to someone else, as for a teacher watching.
      setState(
        room,
        PangeaEventTypes.activityRole,
        '',
        ActivityRolesModel({
          'role2': ActivityRoleModel(
            id: 'role2',
            userId: coursemate,
            role: 'Barista',
            finishedAt: DateTime.utc(2026),
          ),
        }).toJson(),
        sender: coursemate,
        at: DateTime.utc(2026),
      );
      setCard(
        room,
        coursemate,
        ActivitySummaryModel(summary: card(coursemate, 'Theirs.')),
      );

      expect(view(room).cards.map((c) => c.userId), [coursemate]);
    });

    test('offers no feedback once the bot\'s service window has passed', () {
      final room = activityRoom(coursemateDone: true);
      final longAgo = DateTime.now().subtract(
        activitySummaryServiceWindow + const Duration(minutes: 1),
      );
      setCard(
        room,
        learner,
        ActivitySummaryModel(summary: card(learner, 'Old.')),
        at: longAgo,
      );
      setCard(
        room,
        coursemate,
        ActivitySummaryModel(summary: card(coursemate, 'Old.')),
        at: longAgo,
      );

      final own = view(room).cardFor(learner)!;
      expect(own.participant?.feedback, 'Old.');
      expect(own.canRequest, isFalse);
    });

    test('a bot that never wrote and has left offers no retry', () {
      // Members load lazily, so the wait never depends on the bot's membership.
      final room = activityRoom(coursemateDone: true, botJoined: false);
      expect(
        view(
          room,
          waits: {
            learner: ActivitySummaryWait(
              since: DateTime.now(),
              finishedAt: finish,
            ),
          },
        ).cardFor(learner)!.isLoading,
        isTrue,
      );

      final own = view(
        room,
        waits: {
          learner: ActivitySummaryWait(
            since: DateTime.now().subtract(expired),
            finishedAt: finish,
          ),
        },
      ).cardFor(learner)!;
      expect(own.hasFailed, isTrue);
      expect(own.canRequest, isFalse);
    });
  });

  group('rooms from before per-learner cards', () {
    test('render every learner from the bot\'s canonical summary', () {
      final room = activityRoom(coursemateDone: true);
      setSlot(
        room,
        ActivitySummaryStateKeys.canonical,
        ActivitySummaryModel(
          summary: roomSummary('Well done.'),
          langCode: 'fr',
          requestHash: 'row-room',
        ),
      );

      final shown = view(room);
      expect(shown.cards.map((c) => c.userId), [learner, coursemate]);
      expect(
        shown.cardFor(coursemate)?.participant?.feedback,
        'Well done. ($coursemate)',
      );
      expect(shown.cardFor(learner)?.canRequest, isTrue);
      expect(shown.cardFor(learner)?.requestHash, 'row-room');
      expect(shown.groupSummary, 'Well done.');
      expect(shown.groupRequestHash, 'row-room');
      expect(shown.groupLangCode, 'fr');
    });

    test('leave out a learner the room summary has no feedback for', () {
      final room = activityRoom(coursemateDone: true);
      setSlot(
        room,
        ActivitySummaryStateKeys.canonical,
        ActivitySummaryModel(
          summary: roomSummary('Well done.', participants: [learner]),
        ),
      );

      expect(view(room).cards.map((c) => c.userId), [learner]);
    });

    test('ignore a canonical summary anyone but the bot wrote', () {
      final room = activityRoom(coursemateDone: true);
      setSlot(
        room,
        ActivitySummaryStateKeys.canonical,
        ActivitySummaryModel(summary: roomSummary('Forged.')),
        sender: coursemate,
      );

      expect(room.activitySummary, isNull);
      expect(view(room).groupSummary, isNull);
    });

    test('load every card together while the room-wide call runs, and '
        'after any request', () {
      final room = activityRoom(coursemateDone: true);
      setSlot(
        room,
        ActivitySummaryStateKeys.canonical,
        ActivitySummaryModel(requestedAt: DateTime.now()),
      );
      expect(view(room).cards.every((c) => c.isLoading), isTrue);

      final summaryAt = DateTime.now().subtract(const Duration(minutes: 5));
      setSlot(
        room,
        ActivitySummaryStateKeys.canonical,
        ActivitySummaryModel(
          summary: roomSummary('First try.'),
          callStartedTs: summaryAt.millisecondsSinceEpoch,
        ),
        at: summaryAt,
      );
      // An older client's request names nobody.
      setRequest(room, at: DateTime.now());
      expect(view(room).cards.every((c) => c.isLoading), isTrue);
    });

    test('fall back to a summary an older client wrote, without feedback', () {
      final room = activityRoom(coursemateDone: true);
      setSlot(
        room,
        ActivitySummaryStateKeys.legacy,
        ActivitySummaryModel(summary: roomSummary('Unkeyed.')),
        sender: coursemate,
      );
      expect(view(room).groupSummary, 'Unkeyed.');

      setSlot(
        room,
        'en',
        ActivitySummaryModel(summary: roomSummary('Per L1.')),
        sender: coursemate,
      );
      final shown = view(room);
      expect(shown.groupSummary, 'Per L1.');
      // Feedback would reach the bot with no summary of its own to regenerate.
      expect(shown.cardFor(learner)?.canRequest, isFalse);

      setSlot(
        room,
        ActivitySummaryStateKeys.canonical,
        ActivitySummaryModel(summary: roomSummary('The bot\'s.')),
      );
      expect(view(room).groupSummary, 'The bot\'s.');
    });
  });

  group('analytics', () {
    Map<String, dynamic> uses(String userId, String lemma) => {
      userId: [
        {'lemma': lemma, 'type': 'vocab', 'cat': 'n', 'times_used': 1},
      ],
    };
    String? lemmaOf(Room room, String userId) => room
        .activitySummaryAnalytics
        ?.constructs[userId]
        ?.usages
        .values
        .single
        .identifier
        .lemma;

    test('reads each learner from their own slot, else the room\'s, else an '
        'old summary', () {
      final room = activityRoom(coursemateDone: true);
      setSlot(
        room,
        'en',
        ActivitySummaryModel.fromJson({'analytics': uses(learner, 'café')}),
        sender: coursemate,
      );
      expect(lemmaOf(room, learner), 'café');

      setState(
        room,
        PangeaEventTypes.activitySummary,
        ActivitySummaryStateKeys.analytics,
        {...uses(learner, 'leche'), ...uses(coursemate, 'pan')},
        sender: coursemate,
        at: DateTime.now(),
      );
      expect(lemmaOf(room, learner), 'leche');

      setState(
        room,
        PangeaEventTypes.activitySummary,
        ActivitySummaryStateKeys.learnerAnalytics(learner),
        uses(learner, 'azúcar'),
        sender: learner,
        at: DateTime.now(),
      );
      expect(lemmaOf(room, learner), 'azúcar');
      // The coursemate has no slot of their own yet.
      expect(lemmaOf(room, coursemate), 'pan');
    });

    test('ignores a learner\'s slot anyone else wrote', () {
      final room = activityRoom();
      setState(
        room,
        PangeaEventTypes.activitySummary,
        ActivitySummaryStateKeys.learnerAnalytics(learner),
        uses(learner, 'forged'),
        sender: coursemate,
        at: DateTime.now(),
      );
      expect(lemmaOf(room, learner), isNull);
    });

    test('a learner writes theirs when they finish, and again after ending '
        'again', () {
      final room = activityRoom(learnerDone: false);
      expect(room.needsOwnActivityAnalytics, isFalse);

      setRoles(room, learnerDone: true, coursemateDone: false);
      expect(room.needsOwnActivityAnalytics, isTrue);

      setState(
        room,
        PangeaEventTypes.activitySummary,
        ActivitySummaryStateKeys.learnerAnalytics(learner),
        uses(learner, 'café'),
        sender: learner,
        at: DateTime.utc(2026).add(const Duration(seconds: 1)),
      );
      expect(room.needsOwnActivityAnalytics, isFalse);

      // Resumed, then finished again later.
      final roles = room.activityRoles!;
      roles.updateRole(
        ActivityRoleModel(
          id: 'role1',
          userId: learner,
          role: 'Customer',
          finishedAt: DateTime.utc(2026).add(const Duration(minutes: 10)),
        ),
      );
      setState(
        room,
        PangeaEventTypes.activityRole,
        '',
        roles.toJson(),
        sender: learner,
        at: DateTime.utc(2026).add(const Duration(minutes: 10)),
      );
      expect(room.needsOwnActivityAnalytics, isTrue);
    });

    test('an older client\'s room analytics, written after the finish, '
        'need no rewrite', () {
      final room = activityRoom(coursemateDone: true);
      setState(
        room,
        PangeaEventTypes.activitySummary,
        ActivitySummaryStateKeys.analytics,
        uses(learner, 'leche'),
        sender: coursemate,
        at: DateTime.utc(2026).add(const Duration(minutes: 1)),
      );
      expect(room.needsOwnActivityAnalytics, isFalse);
    });
  });
}
