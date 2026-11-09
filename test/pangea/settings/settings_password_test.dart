import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_password/settings_password.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

/// #9751 — a server refusal of the current password is shown under the
/// current-password field; every other failure stays under the repeated one.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentPasswordField = 0;
  const repeatPasswordField = 2;

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // MatrixState.client points the client at Environment.synapseURL, which
    // reads GetStorage (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('settings_password');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  void refusePasswordChange(Map<String, Object?> error) {
    FakeMatrixApi.currentApi!.api['POST']!['/client/v3/account/password'] =
        (_) => throw MatrixException.fromJson(error);
  }

  Future<L10n> submitValidForm(WidgetTester tester) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const SettingsPassword(),
        ),
      ),
    );
    // L10n loads deferred, so the page builds a frame after the app does.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(currentPasswordField), 'not my password');
    await tester.enterText(fields.at(1), 'a new password');
    await tester.enterText(fields.at(repeatPasswordField), 'a new password');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump();

    return L10n.of(tester.element(find.byType(SettingsPassword)));
  }

  String? errorUnder(WidgetTester tester, int field) => tester
      .widget<TextField>(find.byType(TextField).at(field))
      .decoration
      ?.errorText;

  testWidgets('a wrong current password is reported on its own field', (
    tester,
  ) async {
    // Synapse's user-interactive auth answer to a wrong password.
    refusePasswordChange({
      'errcode': 'M_FORBIDDEN',
      'error': 'Invalid username or password',
      'flows': [
        {
          'stages': ['m.login.password'],
        },
      ],
      'params': {},
      'session': 'uia-session',
      'completed': [],
    });

    final l10n = await submitValidForm(tester);

    expect(errorUnder(tester, currentPasswordField), l10n.passwordIsWrong);
    expect(errorUnder(tester, repeatPasswordField), isNull);
  });

  testWidgets('any other failure stays on the repeated-password field', (
    tester,
  ) async {
    refusePasswordChange({
      'errcode': 'M_LIMIT_EXCEEDED',
      'error': 'Too many requests',
    });

    final l10n = await submitValidForm(tester);

    expect(errorUnder(tester, currentPasswordField), isNull);
    expect(
      errorUnder(tester, repeatPasswordField),
      l10n.tooManyRequestsWarning,
    );
  });
}
