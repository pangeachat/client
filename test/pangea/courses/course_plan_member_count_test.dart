import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// Counts member-list reads, answering each with an empty list; everything
/// else goes to [FakeMatrixApi]. Synapse refuses the read for a room the user
/// is not in, so what matters is whether it is sent at all.
class _MembersServer extends http.BaseClient {
  final FakeMatrixApi _fallback = FakeMatrixApi();
  int memberReads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!request.url.path.endsWith('/members')) return _fallback.send(request);
    memberReads++;
    return Future.value(
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'chunk': []}))),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  }
}

/// #9707 — the course plan counts the course's members to dim activities that
/// need more people, and that count is only readable once the learner has
/// joined (CLIENT-EC3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MembersServer server;
  late Client client;

  setUp(() async {
    server = _MembersServer();
    client = await getTestClient(httpClient: server);
    MatrixState.pangeaController = FakePangeaController(client: client);
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<void> pump(WidgetTester tester, Membership membership) async {
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: membership,
      // More members than are known locally, so a count reads the server.
      summary: RoomSummary.fromJson({
        'm.joined_member_count': 3,
        'm.invited_member_count': 0,
        'm.heroes': [],
      }),
    );
    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: CourseObjectivesList(objectivesProvider: loader, room: room),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a course the learner has not joined reads no member list', (
    tester,
  ) async {
    await pump(tester, Membership.invite);
    expect(server.memberReads, 0);
  });

  testWidgets('a joined course still reads its member list', (tester) async {
    await pump(tester, Membership.join);
    expect(server.memberReads, greaterThan(0));
  });
}
