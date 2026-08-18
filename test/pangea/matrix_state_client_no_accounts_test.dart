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

/// Keeps [MatrixState]'s real `client` getter but skips `initMatrix()`, which
/// wires background push, notification listeners and the Pangea controller —
/// none of which the getter reads, and none of which stand up under
/// `flutter test`. `initState` itself reads `client`, so it cannot run here
/// either.
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

/// #8368 — `MatrixState.client` threw `Bad state: No element` on `/home`.
///
/// Single-account logout removes the account from `Matrix.clients` and routes
/// straight to `/home` (the `loggedOut` branch of `_registerSubs`). Every
/// widget that reads `client` while that route builds — auth guards, presence
/// builders, the lifecycle observer — hit an empty list, and the getter's
/// fallback did `currentBundle!.first!`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Client otherClient;
  late SharedPreferences store;

  setUpAll(() async {
    // The getter stamps `AppConfig.defaultHomeserverUri` onto the client it
    // returns, which reads the env layer.
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
    otherClient = await prepareTestClient();
  });

  tearDownAll(() async {
    await client.dispose();
    await otherClient.dispose();
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

  testWidgets('client survives the last account logging out', (tester) async {
    final clients = <Client>[client];
    final state = await pumpMatrix(tester, clients);

    expect(state.client, same(client));

    // What the loggedOut branch does on single-account logout: the list empties
    // while /home is still building.
    clients.remove(client);

    expect(state.client, same(client));
  });

  testWidgets('a remaining account wins over the retained one', (tester) async {
    final clients = <Client>[client, otherClient];
    final state = await pumpMatrix(tester, clients);

    expect(state.client, same(client));

    clients.remove(client);

    // The retained client is a last resort, never a shadow over a live account.
    expect(state.client, same(otherClient));
  });

  testWidgets('a re-added account replaces the retained one', (tester) async {
    final clients = <Client>[client];
    final state = await pumpMatrix(tester, clients);

    expect(state.client, same(client));
    clients.remove(client);
    expect(state.client, same(client));

    // getLoginClient() adds the next account once login begins.
    clients.add(otherClient);

    expect(state.client, same(otherClient));
  });
}
