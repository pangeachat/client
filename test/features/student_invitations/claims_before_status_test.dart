import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_consumer.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/network/choreo_gate.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../pangea/fake_pangea_controller.dart';

/// SPEC: a student with a waiting seat never burns their trial. choreo's HTTP
/// gate auto-claims a trial on ANY gated call (the status read, and
/// grammar_constructs at sign-in, among others), so a seat invitation (or
/// Canvas ticket) the student ticked before signing in must be confirmed
/// before the session's first choreo call: every choreo request waits on it
/// (ChoreoGate, in the shared request layer).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const inv = 'Q2xhc3NJbnZpdGUtMDAx_-';
  const ticket = 'dGlja2V0LWZvci1hLWNhbnZhcy1sZWFybmVyLWxhdW5jaA';
  const userId = '@student:example.org';

  setUpAll(() async {
    sqfliteFfiInit();
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
      if (path.endsWith('/choreo/version')) {
        order.add('version');
        return http.Response('{}', 200);
      }
      if (path.endsWith('/grammar_constructs')) {
        order.add('grammar_constructs');
        return http.Response('{}', 200);
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

  /// Installs the production choreo preflight body (only the Matrix client it
  /// reads the api and token from is replaced) and returns the real
  /// subscription controller, whose status read is one choreo call of many.
  ///
  /// By default it is the exact production preflight
  /// (confirmTickedClaimsBeforeChoreo) over a signed-in Matrix client whose
  /// HTTP goes to the fake module; [module]/[requestTimeout] swap in a
  /// different module behind the same single-flight confirm.
  Future<SubscriptionController> controller({
    http.Client? module,
    Duration? requestTimeout,
  }) async {
    if (module == null && requestTimeout == null) {
      final client = matrix.Client(
        'claims-before-choreo',
        httpClient: http_,
        database: await matrix.MatrixSdkDatabase.init(
          'claims-before-choreo',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
      client.homeserver = Uri.parse('https://matrix.example.org');
      client.accessToken = 'syt_student';
      ChoreoGate.preflight = () => confirmTickedClaimsBeforeChoreo(client);
    } else {
      ChoreoGate.preflight = () => confirmTickedClaimsBeforeStatus(
        api: StudentInvitationApi(
          httpClient: module ?? http_,
          homeserver: Uri.parse('https://matrix.example.org'),
          requestTimeout: requestTimeout ?? const Duration(seconds: 30),
        ),
        accessToken: 'syt_student',
      );
    }
    return SubscriptionController();
  }

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
    final c = await controller();

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

    await initialize(await controller());

    expectBefore('lti_link', 'status', reason: 'the claim must exist first');
  });

  test(
    'nothing unticked is sent early: it waits for the shell to ask',
    () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      await SpaceCodeRepo.setPendingLtiTicket(const PendingLtiTicket(ticket));
      // Written long ago: choreo calls must not keep an unticked entry alive.
      final storage = GetStorage('class_storage');
      final stamp = DateTime.now()
          .subtract(const Duration(minutes: 50))
          .millisecondsSinceEpoch;
      await storage.write(PLocalKey.cachedInvitationAt, stamp);

      await initialize(await controller());

      expect(order, isNot(contains('confirm')));
      expect(order, isNot(contains('lti_link')));
      expect(
        order,
        isNot(contains('hint')),
        reason: 'an unticked entry is not touched before the shell',
      );
      expect(SpaceCodeRepo.pendingInvitation?.invitationId, inv);
      expect(SpaceCodeRepo.pendingLtiTicket?.ticket, ticket);
      expect(
        storage.read(PLocalKey.cachedInvitationAt),
        stamp,
        reason: 'the entry is not rewritten, so it still expires on time',
      );
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
      final c = await controller(module: outdated);

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

      await initialize(await controller(module: slow));

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
    final c = await controller(
      module: silent,
      requestTimeout: const Duration(milliseconds: 200),
    );

    await initialize(c);
    await http.runWithClient(() => c.reinitialize(userId), () => http_);

    expect(confirms, 1);
    expect(order, contains('status'));
    expect(order, isNot(contains('hint')), reason: 'one bounded call only');
    expect(SpaceCodeRepo.pendingInvitation, isNull);
  });

  test('sign-in\'s initialize + reinitialize overlap: the second waits on '
      'the first\'s confirm, which is sent once', () async {
    await SpaceCodeRepo.setPendingInvitation(
      const PendingInvitation(inv, ackedDisclosureVersion: 2),
    );
    final c = await controller();

    // As PangeaController._onLogin: initialize is not awaited before
    // reinitialize starts.
    await http.runWithClient(() async {
      final first = c.initialize(userId);
      final second = c.reinitialize(userId);
      await Future.wait([first, second]);
    }, () => http_);

    expectBefore('confirm', 'status', reason: 'no status read may overtake');
    expect(order.where((o) => o == 'confirm'), hasLength(1));
  });

  test('an arbitrary gated choreo call at sign-in (grammar_constructs) waits '
      'until the confirm resolves', () async {
    await SpaceCodeRepo.setPendingInvitation(
      const PendingInvitation(inv, ackedDisclosureVersion: 2),
    );
    final c = await controller();

    // As sign-in: the status read and other choreo calls start together.
    await http.runWithClient(() async {
      await Future.wait([
        c.initialize(userId),
        Requests(
          accessToken: 'syt_student',
        ).post(url: PApiUrls.grammarConstructs, body: {}),
        // A direct GET, outside any repo.
        Requests(accessToken: 'syt_student').get(url: PApiUrls.appVersion),
      ]);
    }, () => http_);

    expectBefore('confirm', 'grammar_constructs', reason: 'claim first');
    expect(
      order,
      isNot(contains('hint')),
      reason: 'the confirm is the only module call choreo waits on',
    );
    expectBefore('confirm', 'version', reason: 'claim first');
    expectBefore('confirm', 'status', reason: 'claim first');
    expect(order.where((o) => o == 'confirm'), hasLength(1));
  });

  test('a call to a non-choreo host does not wait', () async {
    await SpaceCodeRepo.setPendingInvitation(
      const PendingInvitation(inv, ackedDisclosureVersion: 2),
    );
    await controller();
    var waited = false;
    final run = ChoreoGate.preflight!;
    ChoreoGate.preflight = () {
      waited = true;
      return run();
    };

    await ChoreoGate.beforeRequest(Uri.parse('https://cms.example.org/api'));
    expect(waited, isFalse);
    await ChoreoGate.beforeRequest(Uri.parse(PApiUrls.speechToTextStream));
    expect(waited, isTrue, reason: 'the streaming socket is choreo too');
  });
}
