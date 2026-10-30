import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/invitation_notice.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_flow.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// Spec amendment 2026-10-10 §1: no checkbox anywhere. After sign-in the
/// app opens the stored invitation (`POST …/student_invitations/{id}/open`,
/// body `{}`) at most once, and no email or Matrix id is put in a request
/// URL.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const inv = 'Q2xhc3NJbnZpdGUtMDAx_-';
  const homeserver = 'https://matrix.example.org';
  const prefix = '/_synapse/client/pangea/v1';
  const token = 'syt_student';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('seat_open');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('class_storage');
    dotenv.testLoad(
      mergeWith: {
        'CHOREO_API': 'https://choreo.example.org',
        'SYNAPSE_URL': homeserver,
      },
    );
    await lookupL10n(const Locale('en'));
  });

  late List<http.Request> sent;
  late Map<String, http.Response Function(http.Request)> routes;
  late List<ClaimNotice> notices;
  late MockClient module;

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  setUp(() async {
    sent = [];
    notices = [];
    routes = {
      'POST $prefix/student_invitations/$inv/open': (_) => json(200, {
        'result': 'claimed',
        'invitation_id': inv,
        'room_id': '!c:example.org',
      }),
    };
    await SpaceCodeRepo.clearPendingInvitation();
    module = MockClient((request) async {
      sent.add(request);
      final path = request.url.path;
      if (path.endsWith('/open')) {
        // The open takes a moment, so a test can look while it is in flight.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final handler = routes['${request.method} $path'];
      return handler == null
          ? json(404, {'errcode': 'M_NOT_FOUND'})
          : handler(request);
    });
  });

  StudentInvitationApi api() => StudentInvitationApi(
    httpClient: module,
    homeserver: Uri.parse(homeserver),
  );

  PendingClaimsFlow flow() =>
      PendingClaimsFlow(api: api(), accessToken: token, notify: notices.add);

  Iterable<http.Request> calls(String path) =>
      sent.where((r) => r.url.path == '$prefix/$path');

  group('open on sign-in, at most once', () {
    test('the stored invitation is opened once with an empty body, then '
        'the entry is gone', () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));

      await flow().consumeInvitation();
      await flow().consumeInvitation();

      final open = calls('student_invitations/$inv/open').single;
      expect(open.method, 'POST');
      expect(jsonDecode(open.body), <String, Object?>{});
      expect(open.headers['authorization'], 'Bearer $token');
      expect(SpaceCodeRepo.pendingInvitation, isNull);
      expect(notices.single.kind, ClaimNoticeKind.claimed);
    });

    for (final (body, kind) in [
      ({'result': 'pending'}, ClaimNoticeKind.pendingApproval),
      ({'result': 'pending_approval'}, ClaimNoticeKind.pendingApproval),
      ({'result': 'denied'}, ClaimNoticeKind.denied),
    ]) {
      test('"${body['result']}" is reported as $kind', () async {
        await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
        routes['POST $prefix/student_invitations/$inv/open'] = (_) =>
            json(200, {...body, 'invitation_id': inv, 'room_id': '!c'});

        await flow().consumeInvitation();

        expect(notices.single.kind, kind);
      });
    }

    // Rough edge #1 (hand test 2026-10-28): a student whose invitation went
    // to a teacher for approval was offered "Claim your trial" in
    // onboarding. The open's answer is kept so onboarding can wait instead.
    test('an open that waits for approval is remembered; a claim or a '
        'refusal clears it', () async {
      for (final (result, waiting) in [
        ('pending', true),
        ('claimed', false),
        ('pending_approval', true),
        ('denied', false),
      ]) {
        await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
        routes['POST $prefix/student_invitations/$inv/open'] = (_) => json(
          200,
          {'result': result, 'invitation_id': inv, 'room_id': '!c'},
        );

        await flow().consumeInvitation();

        expect(SpaceCodeRepo.seatApprovalPending, waiting, reason: result);
      }
    });

    test('the invitation counts as unsettled while its open is in flight, '
        'and stays so if the open fails without an answer', () async {
      await SpaceCodeRepo.setSeatApprovalPending(false);
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      routes['POST $prefix/student_invitations/$inv/open'] = (_) =>
          json(500, {'errcode': 'M_UNKNOWN'});

      final opening = flow().consumeInvitation();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(SpaceCodeRepo.pendingInvitation, isNull);
      expect(SpaceCodeRepo.seatInvitationWaiting, isTrue);
      await opening;

      expect(SpaceCodeRepo.seatInvitationWaiting, isTrue);
    });

    test('a gone invitation is reported plainly and not retried', () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      routes.remove('POST $prefix/student_invitations/$inv/open');

      await flow().consumeInvitation();
      await flow().consumeInvitation();

      expect(calls('student_invitations/$inv/open'), hasLength(1));
      expect(notices.single.kind, ClaimNoticeKind.notLive);
    });
  });

  test('no email or Matrix id is ever put in a request URL', () async {
    routes['GET $prefix/student_invitations/hint'] = (_) => json(200, {
      'course_name': 'Spanish 101',
      'masked_email_hint': 'a***@school.edu',
    });
    await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));

    await api().hint(inv);
    await flow().consumeInvitation();

    expect(sent, hasLength(2));
    for (final request in sent) {
      expect(request.url.toString(), isNot(contains('@')));
    }
  });

  group('no checkbox is rendered anywhere', () {
    Widget host(Widget child) => MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('the sign-up/sign-in invitation card', (tester) async {
      routes['GET $prefix/student_invitations/hint'] = (_) => json(200, {
        'course_name': 'Spanish 101',
        'masked_email_hint': 'a***@school.edu',
      });
      const pending = PendingInvitation(inv);
      await SpaceCodeRepo.setPendingInvitation(pending);
      await tester.pumpWidget(
        host(InvitationNotice(pending: pending, api: api())),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Spanish 101'), findsWidgets);
      // True with or without a seat: a course may have none (hand test
      // 2026-10-28), so the line promises only the class.
      expect(
        find.text('Use a***@school.edu so your class finds you.'),
        findsOneWidget,
      );
      expect(find.textContaining('seat'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        sent.where((r) => r.method == 'POST'),
        isEmpty,
        reason: 'nothing is opened before sign-in',
      );
    });
  });
}
