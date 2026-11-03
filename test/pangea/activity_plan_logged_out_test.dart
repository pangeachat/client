import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// The fake controller, but with the REAL [UserController], so the access
/// token is read from the client exactly as the app reads it.
class _RealUserPangeaController extends FakePangeaController {
  _RealUserPangeaController(Client client) : super(client: client);

  final _userController = UserController();

  @override
  UserController get userController => _userController;
}

/// #9738 — an activity plan read that runs just after logout finds no access
/// token. The read cannot go out, and a logged-out client has nothing to fix,
/// so nothing is reported: each one was a CLIENT-ESE event, 10–60 ms after
/// `event: logout`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('plan_logout_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  final repo = ActivityPlanRepo.instance;
  final debugPrintBefore = debugPrint;
  late Client client;
  late List<String> errors;

  setUpAll(() async {
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('activity_plan_storage');
  });

  setUp(() async {
    client = await getTestClient();
    MatrixState.pangeaController = _RealUserPangeaController(client);
    repo.resetForTesting();
    errors = [];
    debugPrint = (message, {wrapWidth}) {
      if (message != null && message.startsWith('error message:')) {
        errors.add(message);
      }
    };
  });

  tearDown(() async {
    debugPrint = debugPrintBefore;
    await client.dispose();
  });

  /// Hydrates [activityId] through the batch fetch, returning every request
  /// that left.
  Future<List<http.Request>> hydrate(String activityId) async {
    final sent = <http.Request>[];
    await http.runWithClient(
      () async {
        repo.ensure(activityId, l1: 'en');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      () => MockClient((request) async {
        sent.add(request);
        return http.Response(
          jsonEncode({
            'activities': {
              activityId: {
                'plan': {
                  'activity_id': activityId,
                  'user_id': '@author:example.com',
                  'roles': [
                    {'role_id': 'r1', 'name': 'Cliente'},
                  ],
                },
                'l1': 'en',
                'version_id': 'v1',
              },
            },
            'removed': [],
            'unavailable': [],
          }),
          200,
        );
      }),
    );
    return sent;
  }

  test('a logged-in client sends the read with its token', () async {
    final sent = await hydrate('logged-in');

    expect(sent, hasLength(1));
    expect(
      sent.single.headers['Authorization'],
      'Bearer ${client.accessToken}',
    );
    expect(errors, isEmpty);
  });

  test('a read after logout sends nothing and reports nothing', () async {
    await client.logout();

    final sent = await hydrate('after-logout');

    expect(sent, isEmpty);
    expect(errors, isEmpty);
  });
}
