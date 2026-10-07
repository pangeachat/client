import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/utils/pending_reports.dart';
import 'package:fluffychat/routes/chat/events/utils/report_api_extension.dart';
import 'package:fluffychat/routes/chat/events/utils/report_flow.dart';
import 'package:fluffychat/routes/chat/events/utils/report_message.dart';
import '../sentry_capture_harness.dart';

/// That a report reaches the module even across a killed app, that nothing
/// the server sends back can carry the reason into a log, that the pointer DM
/// never lands in a room with anyone but the reporter and that admin, and
/// that "Report message" as wired in production really sends the report.
void main() {
  const sentinel = 'REASON-SENTINEL';
  const userId = '@reporter:example.invalid';

  ReportSubmission submission(String id) => ReportSubmission(
    reportId: id,
    roomId: '!room:example.invalid',
    eventId: r'$event:example.invalid',
    reason: '$sentinel for $id',
  );

  MatrixApi apiWith(MockClientHandler handler) => MatrixApi(
    homeserver: Uri.parse('https://hs.example.invalid'),
    accessToken: 'reporter-token',
    httpClient: MockClient(handler),
  );

  group('pending reports survive the app being killed', () {
    late PendingReportStore store;
    late List<Map<String, dynamic>> sentBodies;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = await PendingReportStore.open();
      sentBodies = [];
    });

    Future<CaptureResult> Function(ReportSubmission) serverAnswering(
      int status,
    ) {
      final api = apiWith((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sentBodies.add(body);
        return http.Response(
          jsonEncode(
            status == 200
                ? {'incident_id': 'report:${body['report_id']}'}
                : {'errcode': 'M_UNKNOWN'},
          ),
          status,
          request: request,
        );
      });
      return (report) => attemptReportCapture(api, report);
    }

    test(
      'a stored report is replayed with its original report id, once',
      () async {
        final stored = submission('8a1d0e38-6c43-4d6c-9e57-1c2c0a6a5b11');
        await store.remember(userId, stored);

        // As after a restart: the in-memory cache is gone, only what reached
        // the platform store is left.
        SharedPreferences.resetStatic();
        final afterRestart = await PendingReportStore.open();
        await replayPendingReports(
          newReportId: () => 'rotated-id',
          store: afterRestart,
          userId: userId,
          attempt: serverAnswering(200),
        );

        expect(sentBodies, [stored.toJson()]);
        expect(afterRestart.pending(userId), isEmpty);

        // Confirmed, so the next start sends nothing.
        await replayPendingReports(
          newReportId: () => 'rotated-id',
          store: await PendingReportStore.open(),
          userId: userId,
          attempt: serverAnswering(200),
        );
        expect(sentBodies, hasLength(1));
      },
    );

    test('a report that fails again stays for the next start', () async {
      final stored = submission('id-503');
      await store.remember(userId, stored);

      await replayPendingReports(
        newReportId: () => 'rotated-id',
        store: store,
        userId: userId,
        attempt: serverAnswering(503),
      );

      expect(store.pending(userId).map((r) => r.reportId), ['id-503']);
    });

    test('a conflicting id moves to a new one, stored before the old goes, '
        'and is sent under it', () async {
      await store.remember(userId, submission('id-409'));
      final answers = [409, 200];
      final api = apiWith((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sentBodies.add(body);
        final status = answers.removeAt(0);
        return http.Response(
          jsonEncode(
            status == 200
                ? {'incident_id': 'report:${body['report_id']}'}
                : {'errcode': 'M_UNKNOWN'},
          ),
          status,
          request: request,
        );
      });

      await replayPendingReports(
        newReportId: () => 'rotated-id',
        store: store,
        userId: userId,
        attempt: (report) => attemptReportCapture(api, report),
      );

      expect(sentBodies.map((b) => b['report_id']), ['id-409', 'rotated-id']);
      expect(sentBodies.last['reason'], sentBodies.first['reason']);
      expect(store.pending(userId), isEmpty);
    });

    test(
      'a conflict whose new id also fails is kept under the new id',
      () async {
        await store.remember(userId, submission('id-409'));
        final results = [CaptureResult.conflict, CaptureResult.failed];

        await replayPendingReports(
          newReportId: () => 'rotated-id',
          store: store,
          userId: userId,
          attempt: (_) async => results.removeAt(0),
        );

        expect(store.pending(userId).map((r) => r.reportId), ['rotated-id']);
      },
    );

    test('a 409 is a conflict, not a failure and not a success', () async {
      expect(
        await serverAnswering(409)(submission('id-409')),
        CaptureResult.conflict,
      );
    });

    test(
      'a refused report is kept too: only a confirmation forgets it',
      () async {
        // A homeserver without the module yet also answers 404.
        await store.remember(userId, submission('id-404'));

        await replayPendingReports(
          newReportId: () => 'rotated-id',
          store: store,
          userId: userId,
          attempt: serverAnswering(404),
        );

        expect(store.pending(userId).map((r) => r.reportId), ['id-404']);
      },
    );

    test(
      'only the reporter\'s own reports are replayed with their token',
      () async {
        await store.remember('@someone-else:example.invalid', submission('x'));

        await replayPendingReports(
          newReportId: () => 'rotated-id',
          store: store,
          userId: userId,
          attempt: serverAnswering(200),
        );

        expect(sentBodies, isEmpty);
        expect(store.pending('@someone-else:example.invalid'), hasLength(1));
      },
    );

    test('remember replaces a copy with the same report id', () async {
      await store.remember(userId, submission('same'));
      await store.remember(userId, submission('same'));
      await store.remember(userId, submission('other'));

      expect(store.pending(userId).map((r) => r.reportId).toSet(), {
        'same',
        'other',
      });
      expect(store.pending(userId), hasLength(2));
    });
  });

  group('the pending store under stress', () {
    final harness = SentryCaptureHarness();
    late List<String?> printed;
    late void Function(String?, {int? wrapWidth}) originalDebugPrint;

    setUp(() async {
      await harness.init();
      printed = [];
      originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message);
    });

    tearDown(() async {
      debugPrint = originalDebugPrint;
      await harness.close();
    });

    test('two app copies with stale caches keep both reports', () async {
      SharedPreferences.setMockInitialValues({});
      final tabA = await PendingReportStore.open();
      // A second tab loads its own cache before tab A writes anything.
      SharedPreferences.resetStatic();
      final tabB = await PendingReportStore.open();

      await tabA.remember(userId, submission('from-tab-a'));
      await tabB.remember(userId, submission('from-tab-b'));

      SharedPreferences.resetStatic();
      final afterRestart = await PendingReportStore.open();
      expect(afterRestart.pending(userId).map((r) => r.reportId).toSet(), {
        'from-tab-a',
        'from-tab-b',
      });
    });

    test('replay sees what another app copy stored after it loaded', () async {
      SharedPreferences.setMockInitialValues({});
      final thisTab = await PendingReportStore.open();
      SharedPreferences.resetStatic();
      final otherTab = await PendingReportStore.open();
      await otherTab.remember(userId, submission('from-other-tab'));

      final replayed = <String>[];
      await replayPendingReports(
        newReportId: () => 'rotated-id',
        store: thisTab,
        userId: userId,
        attempt: (report) async {
          replayed.add(report.reportId);
          return CaptureResult.failed;
        },
      );

      expect(replayed, ['from-other-tab']);
    });

    test('a failed forget does not stop the other reports', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _ForgetFails(await SharedPreferences.getInstance());
      await store.remember(userId, submission('first'));
      await store.remember(userId, submission('second'));

      final replayed = <String>[];
      final events = <Object?>[];
      await harness
          .capture(() async {
            await replayPendingReports(
              newReportId: () => 'rotated-id',
              store: store,
              userId: userId,
              attempt: (report) async {
                replayed.add(report.reportId);
                return CaptureResult.recorded;
              },
            );
          })
          .then((event) => events.add(event.throwable));

      expect(replayed.toSet(), {'first', 'second'});
      expect(events, isNotEmpty);
    });

    test('an unreadable stored report is reported without its text', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${PendingReportStore.keyPrefix}|$userId|broken':
            '{"reason":"$sentinel',
      });
      final store = await PendingReportStore.open();
      await store.remember(userId, submission('fine'));

      late List<ReportSubmission> pending;
      final event = await harness.capture(() {
        pending = store.pending(userId);
      });

      expect(pending.map((r) => r.reportId), ['fine']);
      expect(jsonEncode(event.toJson()), isNot(contains(sentinel)));
      expect(printed, isNotEmpty);
      expect(printed.join('\n'), isNot(contains(sentinel)));
    });
  });

  group('nothing the server sends back reaches a log', () {
    final harness = SentryCaptureHarness();
    late List<String?> printed;
    late void Function(String?, {int? wrapWidth}) originalDebugPrint;

    setUp(() async {
      ErrorHandler.resetReportedOnceKeysForTest();
      await harness.init();
      printed = [];
      originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message);
    });

    tearDown(() async {
      debugPrint = originalDebugPrint;
      await harness.close();
    });

    Future<void> expectNoSentinelLeaks(
      MockClientHandler handler, {
      required CaptureResult expected,
      String leaked = sentinel,
    }) async {
      final report = submission('leak-check');
      late CaptureResult result;
      final event = await harness.capture(() async {
        result = await attemptReportCapture(apiWith(handler), report);
      });

      expect(result, expected);
      expect(jsonEncode(event.toJson()), isNot(contains(leaked)));
      expect(event.throwable.toString(), isNot(contains(leaked)));
      expect(printed, isNotEmpty);
      expect(printed.join('\n'), isNot(contains(leaked)));
    }

    test('a truncated 200 that echoes the reason', () async {
      await expectNoSentinelLeaks(
        (request) async =>
            http.Response('{"reason":"$sentinel', 200, request: request),
        expected: CaptureResult.failed,
      );
    });

    test('an error body that echoes the reason', () async {
      await expectNoSentinelLeaks(
        (request) async => http.Response(
          jsonEncode({'error': sentinel, 'detail': sentinel}),
          500,
          request: request,
        ),
        expected: CaptureResult.failed,
      );
    });

    test('an errcode-shaped echo of the reason', () async {
      await expectNoSentinelLeaks(
        (request) async => http.Response(
          jsonEncode({'errcode': 'BULLYING_SENTINEL'}),
          403,
          request: request,
        ),
        expected: CaptureResult.failed,
        leaked: 'BULLYING_SENTINEL',
      );
    });

    test('a malformed Content-Type header', () async {
      await expectNoSentinelLeaks(
        (request) async => http.Response.bytes(
          utf8.encode('{"incident_id": "x"}'),
          200,
          headers: {'content-type': 'application/json; charset=$sentinel'},
          request: request,
        ),
        expected: CaptureResult.failed,
      );
    });

    test('a transport failure whose message quotes the reason', () async {
      await expectNoSentinelLeaks(
        (request) async => throw http.ClientException(sentinel, request.url),
        expected: CaptureResult.failed,
      );
    });

    test('any other failure while reading the answer', () async {
      await expectNoSentinelLeaks(
        (request) async => throw StateError(sentinel),
        expected: CaptureResult.failed,
      );
    });
  });

  group('currentJoinedOrInvited', () {
    test('asks the homeserver, and counts pending invites', () async {
      late Uri asked;
      final api = apiWith((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({
            'chunk': [
              for (final (user, membership) in [
                ('@reporter:x', 'join'),
                ('@admin:x', 'join'),
                ('@invited:x', 'invite'),
                ('@gone:x', 'leave'),
              ])
                {
                  'type': 'm.room.member',
                  'event_id': '\$$user',
                  'room_id': '!dm:x',
                  'sender': user,
                  'state_key': user,
                  'origin_server_ts': 1,
                  'content': {'membership': membership},
                },
            ],
          }),
          200,
          request: request,
        );
      });

      expect(await currentJoinedOrInvited(api, '!dm:x'), {
        '@reporter:x',
        '@admin:x',
        '@invited:x',
      });
      expect(asked.path, '/_matrix/client/v3/rooms/!dm%3Ax/members');
    });
  });

  group('courseRosterFromServer', () {
    test('reads membership and power levels from the homeserver', () async {
      final asked = <String>[];
      final api = apiWith((request) async {
        asked.add(request.url.path);
        if (request.url.path.endsWith('/members')) {
          expect(request.url.queryParameters['membership'], 'join');
          return http.Response(
            jsonEncode({
              'chunk': [
                for (final user in ['@teacher:x', '@student:x', '@demoted:x'])
                  {
                    'type': 'm.room.member',
                    'event_id': '\$$user',
                    'room_id': '!course:x',
                    'sender': user,
                    'state_key': user,
                    'origin_server_ts': 1,
                    'content': {'membership': 'join'},
                  },
              ],
            }),
            200,
            request: request,
          );
        }
        return http.Response(
          jsonEncode({
            'users': {'@teacher:x': 100},
            'users_default': 0,
          }),
          200,
          request: request,
        );
      });

      final roster = await courseRosterFromServer(api, '!course:x');

      expect(roster.joinedPowerLevels, {
        '@teacher:x': 100,
        '@student:x': 0,
        '@demoted:x': 0,
      });
      expect(asked, [
        '/_matrix/client/v3/rooms/!course%3Ax/members',
        '/_matrix/client/v3/rooms/!course%3Ax/state/m.room.power_levels/',
      ]);
    });
  });

  group('reportDmRoomId', () {
    const reporter = '@reporter:x';
    const admin = '@admin:x';
    late int created;

    setUp(() => created = 0);

    Future<String> resolve({required String? existing, Set<String>? members}) =>
        reportDmRoomId(
          existingRoomId: existing,
          reporterId: reporter,
          adminId: admin,
          membersOf: (_) async => members,
          createFresh: () async {
            created++;
            return '!fresh:x';
          },
        );

    test('reuses a DM holding exactly the reporter and the admin', () async {
      expect(
        await resolve(existing: '!dm:x', members: {reporter, admin}),
        '!dm:x',
      );
      expect(created, 0);
    });

    test('a DM someone else was invited into gets a fresh one', () async {
      expect(
        await resolve(
          existing: '!dm:x',
          members: {reporter, admin, '@other-teacher:x'},
        ),
        '!fresh:x',
      );
      expect(created, 1);
    });

    test('a DM the admin has left gets a fresh one', () async {
      expect(await resolve(existing: '!dm:x', members: {reporter}), '!fresh:x');
    });

    test('a DM the reporter is not joined to gets a fresh one', () async {
      expect(await resolve(existing: '!dm:x', members: null), '!fresh:x');
    });

    test('no DM yet: a fresh one', () async {
      expect(await resolve(existing: null), '!fresh:x');
      expect(created, 1);
    });
  });

  group('submitReport, as wired in production', () {
    late Client client;
    late FakeMatrixApi server;
    late List<Map<String, dynamic>> received;
    late List<Set<String>> storedWhenSent;
    late bool serverFails;
    late PendingReportStore store;
    late L10n l10n;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = await PendingReportStore.open();
      l10n = await lookupL10n(const Locale('en'));
      received = [];
      storedWhenSent = [];
      serverFails = false;
      server = FakeMatrixApi()
        ..api['GET']!['/.well-known/matrix/client'] = (req) => {};
      server.api['POST']!['/_synapse/client/pangea/v1/report'] = (body) {
        final decoded = jsonDecode(body as String) as Map<String, dynamic>;
        received.add(decoded);
        // What the device held at the moment the request left: the copy
        // must already be there, before any answer.
        storedWhenSent.add(
          store.pending(client.userID!).map((r) => r.reportId).toSet(),
        );
        return serverFails
            ? {'errcode': 'M_UNKNOWN'}
            : {'incident_id': 'report:${decoded['report_id']}'};
      };
      client = Client(
        'report wiring test',
        httpClient: server,
        verificationMethods: {KeyVerificationMethod.numbers},
        database: await MatrixSdkDatabase.init(
          'report-wiring',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
      await client.checkHomeserver(Uri.parse('https://fakeserver.notexisting'));
      await client.login(
        LoginType.mLoginToken,
        identifier: AuthenticationUserIdentifier(
          user: '@alice:example.invalid',
        ),
        password: '1234',
      );
    });

    tearDown(() => client.dispose(closeDatabase: true));

    test(
      'on start, a logged-in account resends what it left pending',
      () async {
        final left = submission('5b0c2a77-3d3e-4f7e-b4a4-2b8f2f1f9c10');
        await store.remember(client.userID!, left);

        await PendingReportReplay(client: client).start();

        expect(received, [left.toJson()]);
        expect(
          (await PendingReportStore.open()).pending(client.userID!),
          isEmpty,
        );
      },
    );

    /// Reports a message through [submitReport] as a reporter would: "Other",
    /// a reason, OK. [onRetryPrompt] answers the retry prompt if it appears.
    Future<ReportOutcome?> report(
      WidgetTester tester, {
      String? onRetryPrompt,
    }) async {
      late BuildContext chatContext;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                chatContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final room = Room(id: '!room:example.invalid', client: client);
      final event = Event.fromJson({
        'event_id': r'$reported:example.invalid',
        'sender': '@subject:example.invalid',
        'type': EventTypes.Message,
        'origin_server_ts': 1000,
        'content': {'msgtype': 'm.text', 'body': 'MESSAGE-SENTINEL'},
      }, room);

      ReportOutcome? outcome;
      var done = false;
      unawaited(
        submitReport(
          event: event,
          timeline: null,
          context: chatContext,
          client: client,
          flowContext: () => null,
          store: store,
        ).then((result) {
          outcome = result;
          done = true;
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.other));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'he is rude');
      await tester.tap(find.text(l10n.ok));
      // The client answers through real I/O, so real time has to pass too.
      for (
        var i = 0;
        i < 100 && !done && find.text(l10n.reportNotSent).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      if (onRetryPrompt != null) {
        expect(find.text(l10n.reportNotSent), findsOneWidget);
        // The reason dialog may still be animating out beneath the prompt.
        await tester.tap(find.text(onRetryPrompt).last);
        for (var i = 0; i < 100 && !done; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      return outcome;
    }

    testWidgets('sends the report to the module and keeps no copy', (
      tester,
    ) async {
      final outcome = await report(tester);

      expect(outcome, ReportOutcome.captured);
      expect(received, hasLength(1));
      expect(received.single['room_id'], '!room:example.invalid');
      expect(received.single['event_id'], r'$reported:example.invalid');
      expect(received.single['reason'], 'he is rude');
      expect(received.single['report_id'], isA<String>());
      expect(
        storedWhenSent.single,
        {received.single['report_id']},
        reason: 'the copy is written before the request leaves',
      );
      expect(store.pending(client.userID!), isEmpty);
      expect(find.text(l10n.reportSent), findsOneWidget);
    });

    testWidgets('a failed report the reporter gives up on stays stored, '
        'under the id it was sent with', (tester) async {
      serverFails = true;

      final outcome = await report(tester, onRetryPrompt: l10n.cancel);

      expect(outcome, ReportOutcome.notCaptured);
      final kept = store.pending(client.userID!);
      expect(kept.map((r) => r.toJson()), [received.single]);
    });
  });
}

/// A store whose removals always fail, as a full or locked disk would.
class _ForgetFails extends PendingReportStore {
  _ForgetFails(super.prefs);

  @override
  Future<void> forget(String userId, String reportId) async =>
      throw StateError('disk full');
}
