import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/utils/report_api_extension.dart';
import 'package:fluffychat/routes/chat/events/utils/report_flow.dart';
import 'package:fluffychat/routes/chat/events/utils/report_message.dart';
import '../../utils/test_client.dart';
import '../sentry_capture_harness.dart';

/// "Report message", capture first (admin-dash#105; design in the org
/// trust-and-safety.instructions.md, "Teacher surfacing — the Safety page").
///
/// What must hold: the module records every report before any teacher lookup;
/// a retry reuses the report id so it can never be stored twice; an edited
/// message is reported as the revision on screen; and neither the teacher DM
/// nor Sentry carries what the message said or why it was reported.
void main() {
  const reason = 'REASON-SENTINEL he keeps calling me names';
  const messageText = 'MESSAGE-SENTINEL you are an idiot';
  const subjectId = '@subject:example.invalid';
  const reporterId = '@reporter:example.invalid';
  const botId = '@bot:example.invalid';

  const report = ReportSubmission(
    reportId: '3f1c6a52-1f0e-4d43-9a43-7c0c6f6fbb0e',
    roomId: '!room:example.invalid',
    eventId: r'$displayed:example.invalid',
    reason: reason,
  );

  group('captureReport (POST /_synapse/client/pangea/v1/report)', () {
    late http.Request sent;

    MatrixApi apiAnswering(int status, Object body) => MatrixApi(
      homeserver: Uri.parse('https://hs.example.invalid'),
      accessToken: 'reporter-token',
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: const {'content-type': 'application/json'},
          request: request,
        );
      }),
    );

    test('sends the contract body with the reporter token', () async {
      final incidentId = await apiAnswering(200, {
        'incident_id': 'report:${report.reportId}',
      }).captureReport(report);

      expect(incidentId, 'report:${report.reportId}');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/_synapse/client/pangea/v1/report');
      expect(sent.headers['authorization'], 'Bearer reporter-token');
      expect(jsonDecode(sent.body), {
        'report_id': report.reportId,
        'room_id': report.roomId,
        'event_id': report.eventId,
        'reason': reason,
      });
    });

    for (final status in [403, 404, 500]) {
      test('a $status is a typed failure, never a success', () async {
        await expectLater(
          apiAnswering(status, {
            'errcode': 'M_FORBIDDEN',
          }).captureReport(report),
          throwsA(
            isA<PangeaHttpException>().having(
              (e) => e.statusCode,
              'statusCode',
              status,
            ),
          ),
        );
      });
    }

    test('the failure never carries a body that echoes the reason', () async {
      Object? error;
      try {
        await apiAnswering(403, {
          'errcode': 'M_FORBIDDEN',
          'error': 'cannot report: $reason',
        }).captureReport(report);
      } catch (e) {
        error = e;
      }
      expect(error, isA<PangeaHttpException>());
      expect(error.toString(), isNot(contains('REASON-SENTINEL')));
    });

    test('a request that never answers fails instead of hanging', () async {
      final api = MatrixApi(
        homeserver: Uri.parse('https://hs.example.invalid'),
        accessToken: 'reporter-token',
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        api.captureReport(report, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a malformed Content-Type does not lose a confirmation', () async {
      final api = MatrixApi(
        homeserver: Uri.parse('https://hs.example.invalid'),
        accessToken: 'reporter-token',
        httpClient: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({'incident_id': 'report:${report.reportId}'}),
            ),
            200,
            headers: {'content-type': 'application/json; charset="broken'},
            request: request,
          ),
        ),
      );
      expect(await api.captureReport(report), 'report:${report.reportId}');
    });

    test('a 200 naming another report is not taken as recorded', () async {
      await expectLater(
        apiAnswering(200, {
          'incident_id': 'report:some-other-report',
        }).captureReport(report),
        throwsA(isA<ReportCaptureException>()),
      );
    });

    test('a 200 without an incident_id is not taken as recorded', () async {
      await expectLater(
        apiAnswering(200, {}).captureReport(report),
        throwsA(isA<ReportCaptureException>()),
      );
    });
  });

  group('ReportFlow', () {
    late List<String> calls;
    late List<ReportSubmission> captured;
    late List<CaptureResult> captureResults;
    late Set<String> failingWrites;
    late List<bool> retryAnswers;
    late List<ReportRecipient<String>> admins;
    late List<Map<String, Object>> sentContents;
    late L10n l10n;

    setUpAll(() async {
      l10n = await lookupL10n(const Locale('en'));
    });

    setUp(() {
      calls = [];
      captured = [];
      captureResults = [];
      failingWrites = {};
      retryAnswers = [];
      admins = [];
      sentContents = [];
    });

    ReportFlow<String> flow() => ReportFlow<String>(
      capture: (submission) async {
        calls.add('capture');
        captured.add(submission);
        return captureResults.isEmpty
            ? CaptureResult.recorded
            : captureResults.removeAt(0);
      },
      remember: (submission) async {
        calls.add('remember:${submission.reportId}');
        return !failingWrites.contains(submission.reportId);
      },
      forget: (submission) async => calls.add('forget:${submission.reportId}'),
      newReportId: (_) => 'fresh-report-id',
      markRejected: (submission) async {
        calls.add('markRejected:${submission.reportId}');
        return !failingWrites.contains('mark:${submission.reportId}');
      },
      offerRetry: () async {
        calls.add('offerRetry');
        return retryAnswers.removeAt(0);
      },
      confirmCaptured: () => calls.add('confirm'),
      lookupCourseAdmins: () async {
        calls.add('lookup');
        return admins;
      },
      selectRecipients: (found) async {
        calls.add('select');
        return found;
      },
      sendPointer: (recipient, content) async {
        calls.add('send:${recipient.admin}');
        sentContents.add(content);
      },
      pointerBody: l10n.reportPointerMessage,
      recordNonOffensive: (recorded) =>
          calls.add('sentry:${recorded.reportId}'),
    );

    test('an offensive report is captured before any teacher lookup', () async {
      admins = [const ReportRecipient('@teacher:x', 'Spanish 101')];

      final outcome = await flow().run(report, offensive: true);

      expect(outcome, ReportOutcome.captured);
      expect(calls, [
        'remember:${report.reportId}',
        'capture',
        'forget:${report.reportId}',
        'confirm',
        'lookup',
        'select',
        'send:@teacher:x',
      ]);
    });

    test('a report is captured even when no teacher is found', () async {
      admins = [];

      final outcome = await flow().run(report, offensive: true);

      expect(outcome, ReportOutcome.captured);
      expect(captured, [report]);
      expect(calls, [
        'remember:${report.reportId}',
        'capture',
        'forget:${report.reportId}',
        'confirm',
        'lookup',
      ]);
    });

    test(
      'a non-offensive report is captured, with no teacher lookup',
      () async {
        final outcome = await flow().run(report, offensive: false);

        expect(outcome, ReportOutcome.captured);
        expect(captured, [report]);
        expect(calls, [
          'remember:${report.reportId}',
          'capture',
          'forget:${report.reportId}',
          'confirm',
          'sentry:${report.reportId}',
        ]);
      },
    );

    test('every retry resends the same report id', () async {
      captureResults = [
        CaptureResult.failed,
        CaptureResult.failed,
        CaptureResult.recorded,
      ];
      retryAnswers = [true, true];

      final outcome = await flow().run(report, offensive: false);

      expect(outcome, ReportOutcome.captured);
      expect(captured, hasLength(3));
      expect(
        captured.map((s) => s.reportId).toSet(),
        {report.reportId},
        reason: 'a fresh id per attempt could record one report twice',
      );
      expect(captured.map((s) => jsonEncode(s.toJson())).toSet(), {
        jsonEncode(report.toJson()),
      });
      expect(calls, [
        'remember:${report.reportId}',
        'capture',
        'offerRetry',
        'remember:${report.reportId}',
        'capture',
        'offerRetry',
        'remember:${report.reportId}',
        'capture',
        'forget:${report.reportId}',
        'confirm',
        'sentry:${report.reportId}',
      ]);
    });

    test(
      'a declined retry stops: nothing confirmed, nobody notified',
      () async {
        captureResults = [CaptureResult.failed];
        retryAnswers = [false];
        admins = [const ReportRecipient('@teacher:x', 'Spanish 101')];

        final outcome = await flow().run(report, offensive: true);

        expect(outcome, ReportOutcome.notCaptured);
        expect(
          calls,
          ['remember:${report.reportId}', 'capture', 'offerRetry'],
          reason: 'the stored copy must stay for the replay on the next start',
        );
      },
    );

    test(
      'a conflicting id is dropped and the report goes on under a new one',
      () async {
        captureResults = [CaptureResult.conflict, CaptureResult.recorded];
        retryAnswers = [true];

        final outcome = await flow().run(report, offensive: false);

        expect(outcome, ReportOutcome.captured);
        expect(captured.map((s) => s.reportId), [
          report.reportId,
          'fresh-report-id',
        ]);
        expect(captured.last.toJson()..remove('report_id'), {
          'room_id': report.roomId,
          'event_id': report.eventId,
          'reason': report.reason,
        });
        expect(calls, [
          'remember:${report.reportId}',
          'capture',
          'remember:fresh-report-id',
          'forget:${report.reportId}',
          'offerRetry',
          'remember:fresh-report-id',
          'capture',
          'forget:fresh-report-id',
          'confirm',
          'sentry:fresh-report-id',
        ]);
      },
    );

    test(
      'after a conflict, declining keeps only the fresh submission',
      () async {
        captureResults = [CaptureResult.conflict];
        retryAnswers = [false];

        final outcome = await flow().run(report, offensive: false);

        expect(outcome, ReportOutcome.notCaptured);
        expect(calls, [
          'remember:${report.reportId}',
          'capture',
          'remember:fresh-report-id',
          'forget:${report.reportId}',
          'offerRetry',
        ]);
      },
    );

    test('after a conflict, the old copy stays if the new one cannot be '
        'stored', () async {
      captureResults = [CaptureResult.conflict];
      retryAnswers = [false];
      failingWrites = {'fresh-report-id'};

      await flow().run(report, offensive: false);

      expect(calls, isNot(contains('forget:${report.reportId}')));
      expect(
        calls,
        contains('markRejected:${report.reportId}'),
        reason: 'the copy left behind must never be sent as the refused id',
      );
    });

    test(
      'an old id kept by a failed write goes once the new id is recorded',
      () async {
        captureResults = [CaptureResult.conflict, CaptureResult.recorded];
        retryAnswers = [true];
        var failNext = true;
        final forgotten = <String>[];
        final flow = ReportFlow<String>(
          capture: (s) async => captureResults.removeAt(0),
          remember: (s) async {
            if (s.reportId == 'fresh-report-id' && failNext) {
              failNext = false;
              return false;
            }
            return true;
          },
          forget: (s) async => forgotten.add(s.reportId),
          newReportId: (_) => 'fresh-report-id',
          markRejected: (s) async => false,
          offerRetry: () async => retryAnswers.removeAt(0),
          confirmCaptured: () {},
          lookupCourseAdmins: () async => [],
          selectRecipients: (found) async => found,
          sendPointer: (_, _) async {},
          pointerBody: (course) => course,
          recordNonOffensive: (_) {},
        );

        expect(
          await flow.run(report, offensive: false),
          ReportOutcome.captured,
        );
        expect(forgotten.toSet(), {report.reportId, 'fresh-report-id'});
      },
    );

    test('a stored copy is kept until the module confirms it', () async {
      captureResults = [CaptureResult.failed, CaptureResult.failed];
      retryAnswers = [true, false];

      final outcome = await flow().run(report, offensive: false);

      expect(outcome, ReportOutcome.notCaptured);
      expect(calls, isNot(contains('forget:${report.reportId}')));
      expect(
        calls.where((c) => c == 'remember:${report.reportId}'),
        hasLength(2),
      );
    });

    test(
      'the teacher DM is a bare pointer: no text, reason or reported user',
      () async {
        admins = [
          const ReportRecipient('@t1:x', 'Spanish 101'),
          const ReportRecipient('@t2:x', 'French 2'),
        ];

        await flow().run(report, offensive: true);

        expect(sentContents, [
          {
            'msgtype': PangeaEventTypes.report,
            'body': 'A message was reported in Spanish 101 — see Safety',
          },
          {
            'msgtype': PangeaEventTypes.report,
            'body': 'A message was reported in French 2 — see Safety',
          },
        ]);
        final wire = jsonEncode(sentContents);
        expect(wire, isNot(contains('REASON-SENTINEL')));
        expect(wire, isNot(contains('MESSAGE-SENTINEL')));
        expect(wire, isNot(contains(subjectId)));
        expect(wire, isNot(contains(report.eventId)));
      },
    );
  });

  group('reportCourseIds', () {
    CourseRoster course(String id, Map<String, int> joined) =>
        CourseRoster(courseId: id, joinedPowerLevels: joined);

    test('a report about a student goes only to that student\'s courses', () {
      expect(
        reportCourseIds(
          subjectId: subjectId,
          botId: botId,
          courses: [
            course('!a', {subjectId: 0, reporterId: 0}),
            course('!b', {reporterId: 0}),
            course('!c', {subjectId: 50}),
          ],
        ),
        ['!a', '!c'],
      );
    });

    test('a teacher\'s report never reaches the teacher\'s other courses', () {
      expect(
        reportCourseIds(
          subjectId: subjectId,
          botId: botId,
          courses: [
            course('!mine', {subjectId: 0, reporterId: 100}),
            course('!other', {reporterId: 100}),
          ],
        ),
        ['!mine'],
      );
    });

    test(
      'a course admin, or a member who has left, is not a student there',
      () {
        expect(
          reportCourseIds(
            subjectId: subjectId,
            botId: botId,
            courses: [
              course('!admin', {subjectId: 100, reporterId: 0}),
              course('!left', {reporterId: 0}),
            ],
          ),
          isEmpty,
        );
      },
    );

    test('a reported user who is a student in none of the visible courses '
        'is never placed in the reporter\'s courses', () {
      // The module may file this report under a course of the reported
      // user's that the reporter cannot see; pointing the reporter's own
      // admins at their Safety page would send them to a report that is not
      // there.
      expect(
        reportCourseIds(
          subjectId: subjectId,
          botId: botId,
          courses: [
            course('!a', {reporterId: 0}),
            course('!b', {subjectId: 100, reporterId: 0}),
          ],
        ),
        isEmpty,
      );
    });

    test('the bot is never a student', () {
      expect(
        reportCourseIds(
          subjectId: botId,
          botId: botId,
          courses: [
            course('!a', {botId: 50, reporterId: 0}),
          ],
        ),
        isEmpty,
      );
    });
  });

  group('displayedRevisionId', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      room = Room(id: '!room:example.invalid', client: client);
    });

    tearDown(() => client.dispose(closeDatabase: true));

    Event message(String id, String sender, int ts, {String? replaces}) =>
        Event.fromJson({
          'event_id': id,
          'sender': sender,
          'type': EventTypes.Message,
          'origin_server_ts': ts,
          'content': {
            'msgtype': 'm.text',
            'body': replaces == null ? messageText : '* edited $id',
            if (replaces != null) ...{
              'm.new_content': {'msgtype': 'm.text', 'body': 'edited $id'},
              'm.relates_to': {'rel_type': 'm.replace', 'event_id': replaces},
            },
          },
        }, room);

    test('an edited message reports its latest replacement', () {
      final original = message(r'$orig', subjectId, 1000);
      final firstEdit = message(r'$edit1', subjectId, 2000, replaces: r'$orig');
      final latestEdit = message(
        r'$edit2',
        subjectId,
        3000,
        replaces: r'$orig',
      );
      final timeline = Timeline(
        room: room,
        chunk: TimelineChunk(events: [latestEdit, original, firstEdit]),
      );

      expect(displayedRevisionId(original, timeline), r'$edit2');
    });

    test('an unedited message reports itself', () {
      final original = message(r'$orig', subjectId, 1000);
      final timeline = Timeline(
        room: room,
        chunk: TimelineChunk(events: [original]),
      );

      expect(displayedRevisionId(original, timeline), r'$orig');
    });

    test('an "edit" by someone else is not what is displayed', () {
      final original = message(r'$orig', subjectId, 1000);
      final forged = message(r'$forged', reporterId, 2000, replaces: r'$orig');
      final timeline = Timeline(
        room: room,
        chunk: TimelineChunk(events: [forged, original]),
      );

      expect(displayedRevisionId(original, timeline), r'$orig');
    });
  });

  group('recordNonOffensiveReport', () {
    final harness = SentryCaptureHarness();

    setUp(harness.init);
    tearDown(harness.close);

    test('carries the event id and never the reason', () async {
      final event = await harness.capture(
        () => recordNonOffensiveReport(report),
      );

      final wire = jsonEncode(event.toJson());
      expect(wire, contains(report.eventId));
      expect(event.fingerprint, ['user-report', report.eventId]);
      expect(wire, isNot(contains('REASON-SENTINEL')));
      expect(wire, isNot(contains('MESSAGE-SENTINEL')));
    });
  });
}
