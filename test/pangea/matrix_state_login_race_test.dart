import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

/// Keeps [MatrixState]'s real `getLoginClient` guard but skips `initState`
/// (and therefore `initMatrix()`), which wires background push, notification
/// listeners and the Pangea controller — none of which the guard reads, and
/// none of which stand up under `flutter test`. Mirrors
/// `matrix_state_client_no_accounts_test.dart`.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// #8514 — logging out, then immediately logging in as a different account,
/// left the login dialog stuck on "Finalizing..." forever.
///
/// The `loggedOut` listener installed by `_registerSubs` awaits unrelated
/// async work (the analytics update in `handleLoginStateChange`) BEFORE it
/// removes the logged-out client from `Matrix.clients`. If a new login starts
/// during that window, `getLoginClient()` used to see the stale, not-yet-
/// removed client and reuse it — leaving the new login with no
/// `onLoginStateChanged` listener to close the dialog on success.
///
/// `MatrixState.canReuseClientForLogin` now also refuses reuse while the
/// client is marked as tearing down, closing that window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeserver.notexisting'},
    );
    final tempDir = await Directory.systemTemp.createTemp('matrix_state');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    client = await prepareTestClient();
  });

  tearDownAll(() async {
    await client.dispose();
  });

  Future<MatrixState> pumpMatrix(
    WidgetTester tester,
    List<Client> clients,
  ) async {
    await tester.pumpWidget(
      _TestMatrix(clients: clients, store: store, child: const SizedBox()),
    );
    return tester.state<_TestMatrixState>(find.byType(_TestMatrix));
  }

  testWidgets('reuses the logged-out client once its teardown is not pending', (
    tester,
  ) async {
    final state = await pumpMatrix(tester, <Client>[client]);

    expect(state.canReuseClientForLogin, isTrue);
  });

  testWidgets('refuses to reuse a client still unwinding a loggedOut event', (
    tester,
  ) async {
    final state = await pumpMatrix(tester, <Client>[client]);

    // What `_registerSubs`'s listener does the instant it observes
    // `loggedOut`, before it awaits `handleLoginStateChange` and removes
    // the client from `Matrix.clients`.
    state.markClientTearingDownForTest(client);

    expect(state.canReuseClientForLogin, isFalse);
  });

  testWidgets('and keeps refusing while a SECOND same-name client unwinds', (
    tester,
  ) async {
    // Two accounts sharing one client name is the normal case on web, and both
    // can be unwinding at once. Tracked as a set of NAMES this was a counting
    // bug: one entry for two teardowns, so whichever finished first cleared it
    // and a fresh login could take the slot while the other was still tearing
    // down -- the exact race this guard exists to prevent, reachable through
    // the guard itself. The name is busy while any client holding it is.
    final state = await pumpMatrix(tester, <Client>[client]);
    // `prepareTestClient` hardcodes its client name, so a second one shares the
    // first's -- which is the case under test. Built inside `runAsync` because
    // `testWidgets` drives a fake async zone that real database I/O never
    // completes in.
    final sameName = await tester.runAsync(prepareTestClient);

    state.markClientTearingDownForTest(client);
    state.markClientTearingDownForTest(sameName!);

    // The first one finishes its unwind. The second has not.
    state.unmarkClientTearingDownForTest(client);

    expect(
      state.canReuseClientForLogin,
      isFalse,
      reason: 'the other client of that name is still unwinding',
    );
  });
}
