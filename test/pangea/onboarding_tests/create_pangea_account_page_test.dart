import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/registration/create_pangea_account_page.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  // ignore: must_call_super
  void initState() {}

  @override
  Client get client => _client;
}

/// The loading page before onboarding is reached by a redirect, so nothing is
/// behind it, and an account without an L2 is sent back to it. When account
/// setup fails, its ways on are Try again and Log out. See
/// `onboarding.instructions.md`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    client = await getTestClient();
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
  });

  tearDownAll(() => client.dispose());

  testWidgets('a failed setup offers Try again and Log out', (tester) async {
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrixState(client),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const CreatePangeaAccountPage(),
        ),
      ),
    );
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    // The creation date is never seen in a sync here, so the save times out.
    await tester.pump(const Duration(seconds: 31));

    final l10n = L10n.of(tester.element(find.byType(CreatePangeaAccountPage)));
    expect(find.text(l10n.accountSetupFailedHelp), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.tryAgain), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.cancel), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, l10n.logout));
    await tester.pumpAndSettle();

    // Log out goes through the shared logout flow, which asks first.
    expect(find.text(l10n.areYouSureYouWantToLogout), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
  });
}
