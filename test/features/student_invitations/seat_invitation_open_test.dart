import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/invitation_notice.dart';
import 'package:fluffychat/features/student_invitations/lti_link_page.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_consumer.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_flow.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/choreo_gate.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';

/// Spec amendment 2026-10-10 §1: no checkbox anywhere. After sign-in the
/// app opens the stored invitation (`POST …/student_invitations/{id}/open`,
/// body `{}`) at most once, every choreo call waits until that open
/// resolves, and the Canvas link body is just the ticket.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const inv = 'Q2xhc3NJbnZpdGUtMDAx_-';
  const ticket = 'dGlja2V0LWZvci1hLWNhbnZhcy1sZWFybmVyLWxhdW5jaA';
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

  late List<String> order;
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
    order = [];
    sent = [];
    notices = [];
    routes = {
      'POST $prefix/student_invitations/$inv/open': (_) => json(200, {
        'result': 'claimed',
        'invitation_id': inv,
        'room_id': '!c:example.org',
      }),
      'POST $prefix/lti/link': (_) =>
          json(200, {'next': 'app', 'claimed': [], 'login_token': null}),
    };
    await SpaceCodeRepo.clearPendingInvitation();
    await SpaceCodeRepo.clearPendingLtiTicket();
    module = MockClient((request) async {
      sent.add(request);
      final path = request.url.path;
      if (path.endsWith('/open')) {
        // Slower than any choreo call: only an awaited open comes first.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        order.add('open');
      } else if (path.endsWith('/lti/link')) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        order.add('lti_link');
      } else if (path.endsWith('/grammar_constructs')) {
        order.add('grammar_constructs');
        return http.Response('{}', 200);
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

  PendingClaimsFlow flow() => PendingClaimsFlow(
    api: api(),
    accessToken: token,
    notify: notices.add,
    openUrl: (_) async {},
  );

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

    test('a gone invitation is reported plainly and not retried', () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      routes.remove('POST $prefix/student_invitations/$inv/open');

      await flow().consumeInvitation();
      await flow().consumeInvitation();

      expect(calls('student_invitations/$inv/open'), hasLength(1));
      expect(notices.single.kind, ClaimNoticeKind.notLive);
    });
  });

  group('every choreo call waits until open resolves, with no tick', () {
    test('grammar_constructs at sign-in waits for the open', () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      final client = matrix.Client(
        'seat-open',
        httpClient: module,
        database: await matrix.MatrixSdkDatabase.init(
          'seat-open',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
      client.homeserver = Uri.parse(homeserver);
      client.accessToken = token;
      ChoreoGate.preflight = () => openPendingClaimsBeforeChoreo(client);
      addTearDown(() => ChoreoGate.preflight = null);

      await http.runWithClient(
        () => Future.wait([
          Requests(
            accessToken: token,
          ).post(url: PApiUrls.grammarConstructs, body: {}),
          Requests(
            accessToken: token,
          ).post(url: PApiUrls.grammarConstructs, body: {}),
        ]),
        () => module,
      );

      expect(order.where((o) => o == 'open'), hasLength(1));
      expect(order.first, 'open', reason: 'the claim exists first');
      expect(order.where((o) => o == 'grammar_constructs'), hasLength(2));
    });
  });

  group('Canvas L1 body', () {
    test('a learner ticket goes back as just the ticket', () async {
      await SpaceCodeRepo.setPendingLtiTicket(const PendingLtiTicket(ticket));

      await flow().consumeLtiTicket();

      final link = calls('lti/link').single;
      expect(jsonDecode(link.body), {'ticket': ticket});
      expect(link.headers['authorization'], 'Bearer $token');
      expect(notices.single.kind, ClaimNoticeKind.canvasLinked);
      expect(SpaceCodeRepo.pendingLtiTicket, isNull);
    });
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
      expect(find.textContaining('a***@school.edu'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        sent.where((r) => r.method == 'POST'),
        isEmpty,
        reason: 'nothing is opened before sign-in',
      );
    });

    testWidgets('the Canvas link step: Continue is ready at once', (
      tester,
    ) async {
      await SpaceCodeRepo.setPendingLtiTicket(
        const PendingLtiTicket(ticket, courseName: 'Spanish 101'),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: LtiLinkPage(api: api()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(LtiLinkPage.continueKey))
            .onPressed,
        isNotNull,
      );
    });
  });
}
