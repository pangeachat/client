import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/student_invitations/lti_entry.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_flow.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';

/// What the app sends after sign-in for a seat invitation (C2 S1/S2/H1) and
/// a Canvas launch (C5 L1): never a confirmation without the ticked
/// checkbox, and each ferried invitation or ticket returned at most once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('claims_flow_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('class_storage');
  });

  const inv = 'Q2xhc3NJbnZpdGUtMDAx_-';
  const ticket = 'dGlja2V0LWZvci1hLWNhbnZhcy1sZWFybmVyLWxhdW5jaA';
  const homeserver = 'https://matrix.example.org';
  const prefix = '/_synapse/client/pangea/v1';
  const token = 'syt_student_token';

  late List<http.Request> sent;
  late Map<String, http.Response Function(http.Request)> routes;
  late List<ConsentRequest> asked;
  late List<ClaimNotice> notices;
  late List<Uri> opened;
  int? consentAnswer;

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  PendingClaimsFlow flow() => PendingClaimsFlow(
    api: StudentInvitationApi(
      httpClient: MockClient((request) async {
        sent.add(request);
        final handler = routes['${request.method} ${request.url.path}'];
        return handler == null
            ? json(404, {'errcode': 'M_UNRECOGNIZED'})
            : handler(request);
      }),
      homeserver: Uri.parse(homeserver),
    ),
    accessToken: token,
    askConsent: (request) async {
      asked.add(request);
      return consentAnswer;
    },
    notify: notices.add,
    openUrl: (url) async => opened.add(url),
  );

  Iterable<http.Request> calls(String method, String path) =>
      sent.where((r) => r.method == method && r.url.path == '$prefix/$path');

  setUp(() async {
    sent = [];
    asked = [];
    notices = [];
    opened = [];
    consentAnswer = null;
    routes = {
      'GET $prefix/student_invitations/hint': (_) => json(200, {
        'course_name': 'Spanish 101',
        'masked_email_hint': 'a***@school.edu',
      }),
    };
    await SpaceCodeRepo.clearPendingInvitation();
    await SpaceCodeRepo.clearPendingLtiTicket();
  });

  group('confirm not sent without checkbox', () {
    test('no tick before sign-in and "Not now" after: nothing is sent and '
        'the invitation is let go', () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      routes['POST $prefix/student_invitations/confirm'] = (_) => json(200, {
        'result': 'claimed',
        'invitation_id': inv,
        'room_id': '!c',
      });

      await flow().consumeInvitation();

      expect(asked, hasLength(1), reason: 'the confirmation screen is shown');
      expect(asked.single.courseName, 'Spanish 101');
      expect(asked.single.maskedEmailHint, 'a***@school.edu');
      expect(calls('POST', 'student_invitations/confirm'), isEmpty);
      expect(SpaceCodeRepo.pendingInvitation, isNull);
    });

    test('ticked before sign-in: confirm is sent once with that disclosure '
        'version, without asking again', () async {
      await SpaceCodeRepo.setPendingInvitation(
        const PendingInvitation(inv, ackedDisclosureVersion: 2),
      );
      routes['POST $prefix/student_invitations/confirm'] = (_) => json(200, {
        'result': 'claimed',
        'invitation_id': inv,
        'room_id': '!c',
      });

      await flow().consumeInvitation();
      await flow().consumeInvitation();

      expect(asked, isEmpty);
      final confirm = calls('POST', 'student_invitations/confirm').single;
      expect(jsonDecode(confirm.body), {
        'invitation_id': inv,
        'disclosure_version': 2,
      });
      expect(confirm.headers['authorization'], 'Bearer $token');
      expect(notices.single.kind, ClaimNoticeKind.claimed);
      expect(notices.single.courseName, 'Spanish 101');
    });

    test('ticked after sign-in: confirm carries the version shown', () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      consentAnswer = 2;
      routes['POST $prefix/student_invitations/confirm'] = (_) => json(200, {
        'result': 'pending_approval',
        'invitation_id': inv,
        'room_id': '!c',
      });

      await flow().consumeInvitation();

      expect(
        jsonDecode(calls('POST', 'student_invitations/confirm').single.body),
        {'invitation_id': inv, 'disclosure_version': 2},
      );
      expect(notices.single.kind, ClaimNoticeKind.pendingApproval);
    });

    test(
      'an outdated disclosure is shown again and needs a new tick',
      () async {
        await SpaceCodeRepo.setPendingInvitation(
          const PendingInvitation(inv, ackedDisclosureVersion: 1),
        );
        consentAnswer = 3;
        routes['POST $prefix/student_invitations/confirm'] = (request) {
          final version =
              (jsonDecode(request.body) as Map)['disclosure_version'];
          return version == 3
              ? json(200, {
                  'result': 'claimed',
                  'invitation_id': inv,
                  'room_id': '!c',
                })
              : json(409, {'errcode': 'ORG.PANGEA.DISCLOSURE_OUTDATED'});
        };

        await flow().consumeInvitation();

        expect(asked, hasLength(1));
        expect(calls('POST', 'student_invitations/confirm'), hasLength(2));
        expect(notices.single.kind, ClaimNoticeKind.claimed);
      },
    );

    test('an invitation that is no longer live sends nothing', () async {
      await SpaceCodeRepo.setPendingInvitation(
        const PendingInvitation(inv, ackedDisclosureVersion: 2),
      );
      routes['GET $prefix/student_invitations/hint'] = (_) =>
          json(404, {'errcode': 'M_NOT_FOUND'});

      await flow().consumeInvitation();

      expect(calls('POST', 'student_invitations/confirm'), isEmpty);
      expect(notices.single.kind, ClaimNoticeKind.notLive);
      expect(SpaceCodeRepo.pendingInvitation, isNull);
    });
  });

  group('pending prompt shown for matching unconfirmed invitation', () {
    test('a pending invitation is offered and confirmed once ticked', () async {
      routes['GET $prefix/student_invitations/mine/pending'] = (_) =>
          json(200, {
            'invitations': [
              {
                'invitation_id': inv,
                'room_id': '!c',
                'course_name': 'Spanish 101',
              },
            ],
          });
      routes['POST $prefix/student_invitations/confirm'] = (_) => json(200, {
        'result': 'claimed',
        'invitation_id': inv,
        'room_id': '!c',
      });
      consentAnswer = 2;

      await flow().promptPending(<String>{});

      expect(asked.single.courseName, 'Spanish 101');
      expect(asked.single.maskedEmailHint, isNull);
      expect(
        jsonDecode(calls('POST', 'student_invitations/confirm').single.body),
        {'invitation_id': inv, 'disclosure_version': 2},
      );
    });

    test(
      '"Not now" sends nothing and is not asked again this session',
      () async {
        routes['GET $prefix/student_invitations/mine/pending'] = (_) =>
            json(200, {
              'invitations': [
                {
                  'invitation_id': inv,
                  'room_id': '!c',
                  'course_name': 'Spanish 101',
                },
              ],
            });
        final dismissed = <String>{};

        await flow().promptPending(dismissed);
        await flow().promptPending(dismissed);

        expect(asked, hasLength(1));
        expect(calls('POST', 'student_invitations/confirm'), isEmpty);
      },
    );

    test('no pending invitation shows nothing', () async {
      routes['GET $prefix/student_invitations/mine/pending'] = (_) =>
          json(200, {'invitations': []});

      await flow().promptPending(<String>{});

      expect(asked, isEmpty);
    });
  });

  group('learner link ticket survives the sign-up/sign-in bounce and is '
      'returned once after auth', () {
    test('the launch URL is stripped, the ticket ferried, then returned '
        'once with the confirmation and the account token', () async {
      final landing = Uri.parse(
        '${PRoutes.ltiLink}?ticket=$ticket&course=Spanish%20101',
      );
      expect(await LtiEntry.linkRedirect(landing), PRoutes.ltiLink);
      expect(
        await LtiEntry.linkRedirect(Uri.parse(PRoutes.ltiLink)),
        isNull,
        reason: 'the stripped page renders',
      );
      final pending = SpaceCodeRepo.pendingLtiTicket!;
      expect(pending.ticket, ticket);
      expect(pending.instructor, isFalse);
      expect(pending.courseName, 'Spanish 101');

      // The link page records the tick and sends the visitor to sign up.
      await SpaceCodeRepo.setPendingLtiTicket(pending.withAck(2));
      expect(
        PAuthGaurd.isEntryLocation(Uri.parse(PRoutes.ltiLink)),
        isFalse,
        reason: 'a restored session must not yank the link page',
      );

      routes['POST $prefix/lti/link'] = (_) => json(200, {
        'next': 'app',
        'claimed': [
          {'invitation_id': inv, 'room_id': '!c'},
        ],
        'login_token': null,
      });
      await flow().consumeLtiTicket();
      await flow().consumeLtiTicket();

      final link = calls('POST', 'lti/link').single;
      expect(jsonDecode(link.body), {
        'ticket': ticket,
        'confirmed': true,
        'disclosure_version': 2,
      });
      expect(link.headers['authorization'], 'Bearer $token');
      expect(asked, isEmpty);
      expect(notices.single.kind, ClaimNoticeKind.canvasLinked);
      expect(SpaceCodeRepo.pendingLtiTicket, isNull);
    });

    test('an expired ticket is reported and not retried', () async {
      await SpaceCodeRepo.setPendingLtiTicket(
        const PendingLtiTicket(ticket, ackedDisclosureVersion: 2),
      );
      routes['POST $prefix/lti/link'] = (_) =>
          json(410, {'errcode': 'ORG.PANGEA.TICKET_INVALID'});

      await flow().consumeLtiTicket();
      await flow().consumeLtiTicket();

      expect(calls('POST', 'lti/link'), hasLength(1));
      expect(notices.single.kind, ClaimNoticeKind.ticketExpired);
    });
  });

  group('link ticket not returned without the checkbox', () {
    test(
      'an unticked learner ticket asks, and "Not now" sends nothing',
      () async {
        await SpaceCodeRepo.setPendingLtiTicket(
          const PendingLtiTicket(ticket, courseName: 'Spanish 101'),
        );

        await flow().consumeLtiTicket();

        expect(asked.single.courseName, 'Spanish 101');
        expect(calls('POST', 'lti/link'), isEmpty);
        expect(SpaceCodeRepo.pendingLtiTicket, isNull);
      },
    );

    test('ticked in the prompt, the ticket goes with that version', () async {
      await SpaceCodeRepo.setPendingLtiTicket(const PendingLtiTicket(ticket));
      consentAnswer = 2;
      routes['POST $prefix/lti/link'] = (_) =>
          json(200, {'next': 'app', 'claimed': [], 'login_token': null});

      await flow().consumeLtiTicket();

      expect(jsonDecode(calls('POST', 'lti/link').single.body), {
        'ticket': ticket,
        'confirmed': true,
        'disclosure_version': 2,
      });
    });
  });

  group('instructor connect ticket survives the sign-in bounce and returns '
      'to admin-dash once', () {
    test(
      'ferried across sign-in, returned once, admin-dash opened once',
      () async {
        final landing = Uri.parse(
          '${PRoutes.ltiLink}?ticket=$ticket&role=instructor',
        );
        expect(await LtiEntry.linkRedirect(landing), PRoutes.ltiLink);
        expect(SpaceCodeRepo.pendingLtiTicket?.instructor, isTrue);

        const connect =
            'https://admin.example.org/canvas-connect?ticket=c0nn3ct';
        routes['POST $prefix/lti/link'] = (_) =>
            json(200, {'next': 'connect', 'connect_url': connect});

        await flow().consumeLtiTicket();
        await flow().consumeLtiTicket();

        final link = calls('POST', 'lti/link').single;
        expect(jsonDecode(link.body), {'ticket': ticket});
        expect(link.headers['authorization'], 'Bearer $token');
        expect(asked, isEmpty, reason: 'an instructor confirms nothing');
        expect(opened, [Uri.parse(connect)]);
      },
    );

    test('a connect URL that is not http(s) is never opened', () async {
      await SpaceCodeRepo.setPendingLtiTicket(
        const PendingLtiTicket(ticket, instructor: true),
      );
      routes['POST $prefix/lti/link'] = (_) =>
          json(200, {'next': 'connect', 'connect_url': 'javascript:alert(1)'});

      await flow().consumeLtiTicket();

      expect(opened, isEmpty);
      expect(notices.single.kind, ClaimNoticeKind.failed);
    });
  });

  group('lti login token signs in once', () {
    test('the token leaves the URL at once and can be taken only once', () {
      final landing = Uri.parse('${PRoutes.ltiToken}?loginToken=syl_abc123');
      expect(LtiEntry.tokenRedirect(landing), PRoutes.ltiToken);
      expect(LtiEntry.tokenRedirect(Uri.parse(PRoutes.ltiToken)), isNull);
      expect(LtiEntry.takeLoginToken(), 'syl_abc123');
      expect(LtiEntry.takeLoginToken(), isNull);
    });

    test('a landing without a usable token drops an older held one', () {
      LtiEntry.tokenRedirect(Uri.parse('${PRoutes.ltiToken}?loginToken=old'));
      expect(
        LtiEntry.tokenRedirect(Uri.parse('${PRoutes.ltiToken}?x=1')),
        PRoutes.ltiToken,
      );
      expect(LtiEntry.takeLoginToken(), isNull);
    });

    test(
      'the token page is a sign-in entry, so a finished login leaves it',
      () {
        expect(PAuthGaurd.isEntryLocation(Uri.parse(PRoutes.ltiToken)), isTrue);
      },
    );
  });

  test('no email or Matrix id is ever put in a request URL', () async {
    await SpaceCodeRepo.setPendingInvitation(
      const PendingInvitation(inv, ackedDisclosureVersion: 2),
    );
    routes['POST $prefix/student_invitations/confirm'] = (_) =>
        json(200, {'result': 'claimed', 'invitation_id': inv, 'room_id': '!c'});
    routes['GET $prefix/student_invitations/mine/pending'] = (_) =>
        json(200, {'invitations': []});

    await flow().consumeInvitation();
    await flow().promptPending(<String>{});

    for (final request in sent) {
      expect(request.url.toString(), isNot(contains('@')));
    }
  });
}
