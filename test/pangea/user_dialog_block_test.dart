import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #9069 — the profile popup offered "Block" to someone the account had
/// ALREADY blocked, and sent them to the block page with that user's id typed
/// into the block-a-user field, which reads as an instruction to block them a
/// second time. A blocked user gets the opposite offer, and the block page
/// opens with an empty field so the list below it is what they act on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const alice = '@alice:fakeServer.notExisting';

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // The dialog localizes the bot and support display names, which read the
    // environment through GetStorage and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('user_dialog_block');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': '@pangeabot:fakeServer.notExisting',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async => client = await getTestClient());

  tearDown(() async => client.dispose());

  /// The account data a block lives in — what `ignoredUsers` reads, and the
  /// only thing the dialog asks about.
  void block(String userId) =>
      client.accountData['m.ignored_user_list'] = BasicEvent(
        type: 'm.ignored_user_list',
        content: {
          'ignored_users': {userId: <String, Object?>{}},
        },
      );

  Future<GoRouter> pumpDialog(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (inner) => TextButton(
                onPressed: () => UserDialog.show(
                  context: inner,
                  profile: Profile(userId: alice, displayName: 'Alice'),
                  uri: GoRouterState.of(inner).uri,
                ),
                child: const Text('open profile'),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading. The avatar animates while it
    // loads, so the tree never settles.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('open profile'));
    await tester.pump(const Duration(milliseconds: 100));
    return router;
  }

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(UserDialog)));

  String route(GoRouter router) =>
      Uri.decodeFull(router.routeInformationProvider.value.uri.toString());

  testWidgets('an unblocked user is offered Block, seeded into the field', (
    tester,
  ) async {
    final router = await pumpDialog(tester);

    expect(find.text(l10n(tester).unblock), findsNothing);
    await tester.tap(find.text(l10n(tester).block));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      route(router),
      contains('security/ignorelist/$alice'),
      reason: 'blocking is the action, so the field is seeded with the user',
    );
  });

  testWidgets('a blocked user is offered Unblock, with an empty field', (
    tester,
  ) async {
    block(alice);
    final router = await pumpDialog(tester);

    expect(find.text(l10n(tester).block), findsNothing);
    await tester.tap(find.text(l10n(tester).unblock));
    await tester.pump(const Duration(milliseconds: 100));

    expect(route(router), contains('security/ignorelist'));
    expect(
      route(router),
      isNot(contains(alice)),
      reason: 'nothing may seed the block-a-user field of someone unblocking',
    );
  });
}

/// Skips `initMatrix()` — the dialog only wants `Matrix.of(context).client`,
/// not a booted app.
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
