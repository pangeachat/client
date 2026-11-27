import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_stats_menu.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'activity_session_fixtures.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// "I'm done!" with goals left asks first (pangeachat/client#9881): the
/// learner says they finished them all (ends and sends a claim), just ends,
/// or cancels. With every goal earned it ends at once, as before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = testSessionUserId;
  const partner = '@partner:fakeServer.notExisting';

  late Client client;
  late _RoleWriteServer server;
  late List<({String roomId, String roleId, List<String> goalIds})> claims;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:fakeServer.notExisting');
    final tempDir = await Directory.systemTemp.createTemp('end_confirm');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async {
    server = _RoleWriteServer();
    client = await getTestClient(httpClient: server);
    MatrixState.pangeaController = FakePangeaController(client: client);
    MatrixState.pAnyState = PangeaAnyState();
    claims = [];
  });

  tearDown(() async {
    await client.dispose();
  });

  Room roleplay({Map<String, List<String>> awarded = const {}}) {
    final room = activitySessionRoom(
      client,
      roles: {
        'r1': ActivityRoleModel(id: 'r1', userId: me, role: 'Fan'),
        'r2': ActivityRoleModel(id: 'r2', userId: partner, role: 'V'),
      },
      awarded: awarded,
    );
    room.setState(
      activitySessionStateEvent(
        room,
        type: EventTypes.RoomPowerLevels,
        content: {
          'users': {me: 50},
          'users_default': 0,
          'events': {
            PangeaEventTypes.activityRole: 0,
            PangeaEventTypes.activitySummary: 0,
          },
        },
      ),
    );
    return room;
  }

  /// Whether this learner's role was written as ended.
  bool roleEnded() => server.roleWrites > 0;

  Future<L10n> pumpOpenHeader(WidgetTester tester, Room room) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 900.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              ActivityStatsMenu(
                visibilityNotifier: ValueNotifier(true),
                setShowDropdown: (_) {},
                activeGoalNotifier: ValueNotifier<ActivityRoleGoal?>(null),
                room: room,
                claimGoals:
                    ({
                      required String roomId,
                      required String roleId,
                      required List<String> goalIds,
                    }) async {
                      claims.add((
                        roomId: roomId,
                        roleId: roleId,
                        goalIds: goalIds,
                      ));
                    },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return L10n.of(tester.element(find.byType(Scaffold)));
  }

  /// Lets the role write behind the loading dialog finish. The client reads
  /// the fake server's answer on the real clock (it was built outside the
  /// test's fake one), so wait on real time until the dialog closes.
  Future<void> settleEnding(WidgetTester tester) async {
    final loading = find.byWidgetPredicate((w) => w is LoadingDialog);
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 100 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(loading, findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> tapDone(WidgetTester tester, L10n l10n) async {
    await tester.tap(find.text(l10n.completeActivityButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settleEnding(tester);
  }

  testWidgets('with goals left, "I\'m done!" offers three choices', (
    tester,
  ) async {
    final l10n = await pumpOpenHeader(tester, roleplay());
    await tapDone(tester, l10n);

    expect(find.text(l10n.endActivityGoalsLeftTitle), findsOneWidget);
    expect(find.text(l10n.endActivityFinishedAllGoals), findsOneWidget);
    expect(find.text(l10n.endActivityJustEnd), findsOneWidget);
    expect(find.text(l10n.cancel), findsOneWidget);
    expect(roleEnded(), isFalse);
  });

  testWidgets('Cancel leaves the activity open and sends nothing', (
    tester,
  ) async {
    final l10n = await pumpOpenHeader(tester, roleplay());
    await tapDone(tester, l10n);
    await choose(tester, l10n.cancel);

    expect(find.text(l10n.endActivityGoalsLeftTitle), findsNothing);
    expect(roleEnded(), isFalse);
    expect(claims, isEmpty);
  });

  testWidgets('Just end it ends the role and sends no claim', (tester) async {
    final l10n = await pumpOpenHeader(tester, roleplay());
    await tapDone(tester, l10n);
    await choose(tester, l10n.endActivityJustEnd);

    expect(roleEnded(), isTrue);
    expect(claims, isEmpty);
  });

  testWidgets('I finished all my goals ends the role and claims only the '
      'unearned goals', (tester) async {
    final l10n = await pumpOpenHeader(
      tester,
      roleplay(
        awarded: {
          'r1': ['slug-1'],
        },
      ),
    );
    await tapDone(tester, l10n);
    await choose(tester, l10n.endActivityFinishedAllGoals);

    expect(roleEnded(), isTrue);
    expect(claims, hasLength(1));
    expect(claims.single.roomId, testSessionRoomId);
    expect(claims.single.roleId, 'r1');
    expect(claims.single.goalIds, ['slug-2', 'slug-3']);
  });

  testWidgets('with every goal earned, "I\'m done!" ends at once', (
    tester,
  ) async {
    final l10n = await pumpOpenHeader(
      tester,
      roleplay(
        awarded: {
          'r1': ['slug-1', 'slug-2', 'slug-3'],
        },
      ),
    );
    await tapDone(tester, l10n);
    await settleEnding(tester);

    expect(find.text(l10n.endActivityGoalsLeftTitle), findsNothing);
    expect(roleEnded(), isTrue);
    expect(claims, isEmpty);
  });
}

/// Answers the role write that ending sends; everything else goes to the
/// shared fake, which has no route for this state type.
class _RoleWriteServer extends http.BaseClient {
  final FakeMatrixApi _fallback = FakeMatrixApi();
  int roleWrites = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRoleWrite =
        request.method == 'PUT' &&
        request.url.path.contains('/state/${PangeaEventTypes.activityRole}');
    if (!isRoleWrite) return _fallback.send(request);
    roleWrites++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'event_id': r'$role'}))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
