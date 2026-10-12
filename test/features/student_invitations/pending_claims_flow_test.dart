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

/// The Canvas hand-offs (C5 L1, `/lti/link`, `/lti/token`): each ferried
/// ticket returned at most once, the login token used once, and no email or
/// Matrix id in any request URL. Opening an invitation is covered by
/// seat_invitation_open_test.dart.
/// The browser's URL fragment, as LtiEntry reads and clears it.
class FakeFragment implements LtiFragment {
  String? value;

  @override
  String? take() {
    final taken = value;
    value = null;
    return taken;
  }
}

final fragment = FakeFragment();

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
  late List<ClaimNotice> notices;
  late List<Uri> opened;

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
    notify: notices.add,
    openUrl: (url) async => opened.add(url),
  );

  Iterable<http.Request> calls(String method, String path) =>
      sent.where((r) => r.method == method && r.url.path == '$prefix/$path');

  setUp(() async {
    fragment.value = null;
    LtiEntry.fragment = fragment;
    sent = [];
    notices = [];
    opened = [];
    routes = {
      'GET $prefix/student_invitations/hint': (_) => json(200, {
        'course_name': 'Spanish 101',
        'masked_email_hint': 'a***@school.edu',
      }),
    };
    await SpaceCodeRepo.clearPendingInvitation();
    await SpaceCodeRepo.clearPendingLtiTicket();
  });

  group('learner link ticket survives the sign-up/sign-in bounce and is '
      'returned once after auth', () {
    test('the launch URL is stripped, the ticket ferried, then returned '
        'once with the account token', () async {
      // C5.2: the ticket arrives in the URL fragment, which no web host
      // logs; the router sees the bare path.
      fragment.value = 'ticket=$ticket&course=Spanish%20101';
      expect(
        await LtiEntry.linkRedirect(Uri.parse(PRoutes.ltiLink)),
        isNull,
        reason: 'the page renders once the fragment is taken',
      );
      expect(fragment.value, isNull, reason: 'the fragment is cleared');
      expect(
        await LtiEntry.linkRedirect(Uri.parse(PRoutes.ltiLink)),
        isNull,
        reason: 'a re-run finds nothing and keeps the ferried ticket',
      );
      final pending = SpaceCodeRepo.pendingLtiTicket!;
      expect(pending.ticket, ticket);
      expect(pending.instructor, isFalse);
      expect(pending.courseName, 'Spanish 101');

      // The link page sends the visitor to sign up; the ticket waits.
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
      expect(jsonDecode(link.body), {'ticket': ticket});
      expect(link.headers['authorization'], 'Bearer $token');
      expect(notices.single.kind, ClaimNoticeKind.canvasLinked);
      expect(SpaceCodeRepo.pendingLtiTicket, isNull);
    });

    test(
      'a ticket in the query (logged by web hosts) is never ferried, only '
      'stripped from the address bar, and it drops an older held one',
      () async {
        fragment.value = null;
        await SpaceCodeRepo.setPendingLtiTicket(
          const PendingLtiTicket('older'),
        );
        expect(
          await LtiEntry.linkRedirect(
            Uri.parse('${PRoutes.ltiLink}?ticket=$ticket'),
          ),
          PRoutes.ltiLink,
        );
        expect(SpaceCodeRepo.pendingLtiTicket, isNull);
      },
    );

    test('an expired ticket is reported and not retried', () async {
      await SpaceCodeRepo.setPendingLtiTicket(const PendingLtiTicket(ticket));
      routes['POST $prefix/lti/link'] = (_) =>
          json(410, {'errcode': 'ORG.PANGEA.TICKET_INVALID'});

      await flow().consumeLtiTicket();
      await flow().consumeLtiTicket();

      expect(calls('POST', 'lti/link'), hasLength(1));
      expect(notices.single.kind, ClaimNoticeKind.ticketExpired);
    });
  });

  group('instructor connect ticket survives the sign-in bounce and returns '
      'to admin-dash once', () {
    test(
      'ferried across sign-in, returned once, admin-dash opened once',
      () async {
        fragment.value = 'ticket=$ticket&role=instructor';
        expect(await LtiEntry.linkRedirect(Uri.parse(PRoutes.ltiLink)), isNull);
        expect(SpaceCodeRepo.pendingLtiTicket?.instructor, isTrue);

        const connect =
            'https://admin.example.org/canvas-connect#ticket=c0nn3ct';
        routes['POST $prefix/lti/link'] = (_) =>
            json(200, {'next': 'connect', 'connect_url': connect});

        await flow().consumeLtiTicket();
        await flow().consumeLtiTicket();

        final link = calls('POST', 'lti/link').single;
        expect(jsonDecode(link.body), {'ticket': ticket});
        expect(link.headers['authorization'], 'Bearer $token');
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
      fragment.value = 'loginToken=syl_abc123';
      expect(LtiEntry.tokenRedirect(Uri.parse(PRoutes.ltiToken)), isNull);
      expect(fragment.value, isNull, reason: 'the fragment is cleared');
      expect(LtiEntry.tokenRedirect(Uri.parse(PRoutes.ltiToken)), isNull);
      expect(LtiEntry.takeLoginToken(), 'syl_abc123');
      expect(LtiEntry.takeLoginToken(), isNull);
    });

    test('a landing without a usable token drops an older held one', () {
      fragment.value = 'loginToken=old';
      LtiEntry.tokenRedirect(Uri.parse(PRoutes.ltiToken));
      fragment.value = 'x=1';
      expect(LtiEntry.tokenRedirect(Uri.parse(PRoutes.ltiToken)), isNull);
      expect(LtiEntry.takeLoginToken(), isNull);
    });

    test('a token in the query (logged by web hosts) is never used, only '
        'stripped from the address bar, and it drops an older held one', () {
      fragment.value = 'loginToken=older';
      LtiEntry.tokenRedirect(Uri.parse(PRoutes.ltiToken));
      fragment.value = null;
      expect(
        LtiEntry.tokenRedirect(
          Uri.parse('${PRoutes.ltiToken}?loginToken=syl_query'),
        ),
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
    await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
    await SpaceCodeRepo.setPendingLtiTicket(const PendingLtiTicket(ticket));
    routes['POST $prefix/student_invitations/$inv/open'] = (_) =>
        json(200, {'result': 'claimed', 'invitation_id': inv, 'room_id': '!c'});
    routes['POST $prefix/lti/link'] = (_) =>
        json(200, {'next': 'app', 'claimed': [], 'login_token': null});

    await flow().consumeClaims();

    expect(sent, hasLength(2));
    for (final request in sent) {
      expect(request.url.toString(), isNot(contains('@')));
    }
  });
}
