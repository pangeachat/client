import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_consumer.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../pangea/fake_pangea_controller.dart';

/// SPEC: a student with a waiting seat never burns their trial. choreo
/// auto-claims a trial on the first subscription status read, so a seat
/// invitation (or Canvas ticket) the student ticked before signing in must
/// be confirmed BEFORE that read: the subscription controller's initialize,
/// which runs right after sign-in or registration and before onboarding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const inv = 'Q2xhc3NJbnZpdGUtMDAx_-';
  const ticket = 'dGlja2V0LWZvci1hLWNhbnZhcy1sZWFybmVyLWxhdW5jaA';
  const userId = '@student:example.org';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('before_status');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('class_storage');
    dotenv.testLoad(
      mergeWith: {
        'CHOREO_API': 'https://choreo.example.org',
        'SYNAPSE_URL': 'https://matrix.example.org',
      },
    );
  });

  late List<String> order;
  late MockClient http_;
  late Future<http.Response> Function(http.Request) respond;

  setUp(() async {
    order = [];
    await SpaceCodeRepo.clearPendingInvitation();
    await SpaceCodeRepo.clearPendingLtiTicket();
    final fake = FakePangeaController(accessToken: 'syt_student');
    fake.userController.initCompleter.complete();
    MatrixState.pangeaController = fake;
    respond = (request) async {
      final path = request.url.path;
      if (path.endsWith('/student_invitations/hint')) {
        order.add('hint');
        return http.Response(jsonEncode({'course_name': 'Spanish 101'}), 200);
      }
      if (path.endsWith('/student_invitations/confirm')) {
        // Slower than the status read would be: only an awaited confirm
        // can still come first.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        order.add('confirm');
        return http.Response(
          jsonEncode({
            'result': 'claimed',
            'invitation_id': inv,
            'room_id': '!c:example.org',
          }),
          200,
        );
      }
      if (path.endsWith('/lti/link')) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        order.add('lti_link');
        return http.Response(
          jsonEncode({'next': 'app', 'claimed': [], 'login_token': null}),
          200,
        );
      }
      if (path.endsWith('/subscription/status')) {
        order.add('status');
        return http.Response('{}', 200);
      }
      if (path.contains('free_trial') || path.contains('trial')) {
        order.add('trial');
        return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    };
    http_ = MockClient(respond);
  });

  // The production hook body; only the Matrix client it reads the api and
  // token from is replaced.
  SubscriptionController controller({
    http.Client? module,
    Duration requestTimeout = const Duration(seconds: 30),
  }) => SubscriptionController(
    beforeStatus: () => confirmTickedClaimsBeforeStatus(
      api: StudentInvitationApi(
        httpClient: module ?? http_,
        homeserver: Uri.parse('https://matrix.example.org'),
        requestTimeout: requestTimeout,
      ),
      accessToken: 'syt_student',
    ),
  );

  /// Both happened, [first] before [then].
  void expectBefore(String first, String then, {required String reason}) {
    expect(order, containsAll([first, then]), reason: reason);
    expect(order.indexOf(first), lessThan(order.indexOf(then)), reason: reason);
  }

  Future<void> initialize(SubscriptionController c) =>
      http.runWithClient(() => c.initialize(userId), () => http_);

  test('a ticked invitation is confirmed before the first status read, '
      'once', () async {
    await SpaceCodeRepo.setPendingInvitation(
      const PendingInvitation(inv, ackedDisclosureVersion: 2),
    );
    final c = controller();

    await initialize(c);
    await http.runWithClient(() => c.reinitialize(userId), () => http_);

    expectBefore('confirm', 'status', reason: 'the claim must exist first');
    expect(order.where((o) => o == 'confirm'), hasLength(1));
    expect(order, contains('status'));
    expect(SpaceCodeRepo.pendingInvitation, isNull);
  });

  test('a ticked Canvas learner ticket is returned before the first status '
      'read', () async {
    await SpaceCodeRepo.setPendingLtiTicket(
      const PendingLtiTicket(ticket, ackedDisclosureVersion: 2),
    );

    await initialize(controller());

    expectBefore('lti_link', 'status', reason: 'the claim must exist first');
  });

  test(
    'nothing unticked is sent early: it waits for the shell to ask',
    () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      await SpaceCodeRepo.setPendingLtiTicket(const PendingLtiTicket(ticket));

      await initialize(controller());

      expect(order, isNot(contains('confirm')));
      expect(order, isNot(contains('lti_link')));
      expect(
        order,
        isNot(contains('hint')),
        reason: 'an unticked entry is not touched before the shell',
      );
      expect(SpaceCodeRepo.pendingInvitation?.invitationId, inv);
      expect(SpaceCodeRepo.pendingLtiTicket?.ticket, ticket);
    },
  );

  test(
    'an outdated tick is put back unticked for the shell, never lost',
    () async {
      await SpaceCodeRepo.setPendingInvitation(
        const PendingInvitation(inv, ackedDisclosureVersion: 1),
      );
      final outdated = MockClient((request) async {
        if (request.url.path.endsWith('/student_invitations/confirm')) {
          order.add('confirm');
          return http.Response(
            jsonEncode({'errcode': 'ORG.PANGEA.DISCLOSURE_OUTDATED'}),
            409,
          );
        }
        return respond(request);
      });
      final c = controller(module: outdated);

      await initialize(c);

      expect(order.where((o) => o == 'confirm'), hasLength(1));
      final back = SpaceCodeRepo.pendingInvitation;
      expect(back?.invitationId, inv);
      expect(back?.ackedDisclosureVersion, isNull);
    },
  );

  test(
    'a slow module is waited for: status never overtakes the confirm',
    () async {
      await SpaceCodeRepo.setPendingInvitation(
        const PendingInvitation(inv, ackedDisclosureVersion: 2),
      );
      final slow = MockClient((request) async {
        if (request.url.path.endsWith('/student_invitations/confirm')) {
          await Future<void>.delayed(const Duration(seconds: 11));
        }
        return respond(request);
      });

      await initialize(controller(module: slow));

      expectBefore(
        'confirm',
        'status',
        reason: 'no cut-off may let status run while the confirm is in flight',
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test('a module that never answers is bounded by the request timeout, and '
      'the invitation is not resent', () async {
    await SpaceCodeRepo.setPendingInvitation(
      const PendingInvitation(inv, ackedDisclosureVersion: 2),
    );
    var confirms = 0;
    final silent = MockClient((request) async {
      if (request.url.path.endsWith('/student_invitations/confirm')) {
        confirms++;
        return Completer<http.Response>().future;
      }
      return respond(request);
    });
    final c = controller(
      module: silent,
      requestTimeout: const Duration(milliseconds: 200),
    );

    await initialize(c);
    await http.runWithClient(() => c.reinitialize(userId), () => http_);

    expect(confirms, 1);
    expect(order, contains('status'));
    expect(SpaceCodeRepo.pendingInvitation, isNull);
  });
}
