import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/member_analytics_profiles_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';
import 'sentry_capture_harness.dart';

const _path = '/_synapse/client/pangea/v1/member_analytics_profiles';
const _roomId = '!course:fakeServer.notExisting';
const _viewer = '@test:fakeServer.notExisting';
const _bob = '@bob:fakeServer.notExisting';
const _carol = '@carol:fakeServer.notExisting';

/// Answers the member_analytics_profiles module itself and forwards every
/// other request (login included) to a [FakeMatrixApi].
class _ModuleStub extends http.BaseClient {
  int status = 200;
  Map<String, Object?> profiles = {};
  final requests = <Uri>[];
  final _fake = FakeMatrixApi();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path != _path) return _fake.send(request);
    requests.add(request.url);
    final body = status == 200 ? {'profiles': profiles} : {'errcode': 'M_X'};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      request: request,
    );
  }
}

Map<String, Object?> _field(int stars) => {
  'pangea.analytics_profile': {
    'target_language': 'es',
    'analytics': {
      'es': {'level': 2, 'xp_offset': 0, 'stars': stars},
    },
  },
};

AnalyticsProfileModel _model(int stars) => AnalyticsProfileModel(
  targetLanguage: 'es',
  languageAnalytics: {'es': LanguageAnalyticsProfileEntry(2, 0, stars: stars)},
);

/// #9465: the course Leaderboard reads every joined member's profile in one
/// request (member-analytics-profiles.instructions.md, synapse-pangea-chat)
/// and fetches one at a time only the members that read lacks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ModuleStub stub;
  late Client client;

  setUp(() async {
    stub = _ModuleStub();
    client = await getTestClient(httpClient: stub);
  });

  tearDown(() => client.dispose());

  group('repo', () {
    final harness = SentryCaptureHarness();

    setUp(() async {
      ErrorHandler.resetReportedOnceKeysForTest();
      await harness.init();
    });

    tearDown(() => harness.close());

    test('parses each member, an empty profile included', () async {
      stub.profiles = {_bob: _field(7), _carol: {}};

      final profiles = (await client.getMemberAnalyticsProfiles(
        _roomId,
      )).asValue!.value;

      expect(stub.requests.single.queryParameters, {'room_id': _roomId});
      expect(profiles.keys, unorderedEquals([_bob, _carol]));
      expect(profiles[_bob]!.starsByLanguage('es'), 7);
      expect(profiles[_carol]!.isEmpty, isTrue);
    });

    test('a server without the module answers empty and reports '
        'nothing', () async {
      stub.status = 404;
      late Map<String, AnalyticsProfileModel>? profiles;

      await harness.expectNoReport(() async {
        profiles = (await client.getMemberAnalyticsProfiles(
          _roomId,
        )).asValue?.value;
      });

      expect(profiles, isEmpty);
    });

    test('any other failure is reported once and returned as an '
        'error', () async {
      stub.status = 500;
      late Future<bool> isError;

      final event = await harness.capture(() {
        isError = client
            .getMemberAnalyticsProfiles(_roomId)
            .then((r) => r.isError);
      });

      expect(await isError, isTrue);
      expect(event.throwable.toString(), contains('500'));
    });
  });

  group('LoadParticipantsBuilder', () {
    /// A joined course whose member list is already complete: the viewer,
    /// Bob and Carol. The fallback controller would rank Bob at 99 stars
    /// and Carol at 3, so the stars each ends up with say which path served
    /// them.
    Room course() {
      MatrixState.pangeaController = FakePangeaController(
        analyticsProfiles: {_bob: _model(99), _carol: _model(3)},
      );
      final room = Room(
        id: _roomId,
        client: client,
        membership: Membership.join,
        summary: RoomSummary.fromJson({
          'm.joined_member_count': 3,
          'm.invited_member_count': 0,
          'm.heroes': <String>[],
        }),
      );
      for (final id in [_viewer, _bob, _carol]) {
        room.setState(
          Event(
            type: EventTypes.RoomMember,
            content: {'membership': 'join'},
            stateKey: id,
            senderId: id,
            eventId: '\$member$id',
            originServerTs: DateTime.now(),
            room: room,
          ),
        );
      }
      return room;
    }

    Future<LoadParticipantsBuilderState> load(
      WidgetTester tester,
      Room room,
    ) async {
      late LoadParticipantsBuilderState state;
      await tester.pumpWidget(
        MaterialApp(
          home: LoadParticipantsBuilder(
            room: room,
            loadProfiles: true,
            builder: (context, s) {
              state = s;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // The member list and profile reads cross real I/O (the SDK's
      // database), so let real time pass between frames.
      for (var i = 0; i < 100 && state.loading; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(state.loading, isFalse);
      return state;
    }

    int? stars(LoadParticipantsBuilderState state, String userId) =>
        state.getAnalyticsProfile(userId)?.starsByLanguage('es');

    testWidgets('uses the one read, and fetches alone only a member it '
        'lacks', (tester) async {
      stub.profiles = {_viewer: {}, _bob: _field(5)};

      final state = await load(tester, course());

      expect(stub.requests, hasLength(1));
      expect(stars(state, _bob), 5);
      expect(stars(state, _carol), 3);
    });

    testWidgets('falls back to one fetch per member on a server without '
        'the module', (tester) async {
      stub.status = 404;

      final state = await load(tester, course());

      expect(stars(state, _bob), 99);
      expect(stars(state, _carol), 3);
    });
  });
}
