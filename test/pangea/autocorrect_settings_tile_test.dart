import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/autocorrect_settings_tile.dart';
import 'package:fluffychat/routes/settings/settings_learning/enable_autocorrect_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #8112 — on web the autocorrect toggle is disabled with a "Mobile only"
/// subtitle instead of opening a warning dialog. Tapping the disabled tile
/// shows a snackbar warning, which stops appearing after a few attempts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mobileOnlyLabel = 'Mobile only';
  const snackBarWarning =
      'Device autocorrect is only available on the mobile app.';

  late Client client;

  setUpAll(() async {
    // The view model listens to the user controller's profile streams, so it
    // needs a controller to reach through MatrixState. The controller builds a
    // PLanguageStore, which reads its cache from shared preferences.
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient();
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
  });

  tearDownAll(() => client.dispose());

  LearningSettingsViewModel makeViewModel({bool autocorrectOn = false}) =>
      LearningSettingsViewModel(
        Profile(
          userSettings: UserSettings(),
          toolSettings: UserToolSettings(enableAutocorrect: autocorrectOn),
        ),
      );

  Future<void> pumpTile(
    WidgetTester tester,
    LearningSettingsViewModel viewModel, {
    required bool isWeb,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: AutocorrectSettingsTile(viewModel: viewModel, isWeb: isWeb),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapTile(WidgetTester tester) async {
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Fire the snackbar's auto-dismiss timer and its exit animation.
  Future<void> dismissSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  }

  group('on web', () {
    testWidgets('switch is disabled with a "Mobile only" subtitle', (
      tester,
    ) async {
      await pumpTile(tester, makeViewModel(), isWeb: true);

      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.onChanged, isNull);
      expect(find.text(mobileOnlyLabel), findsOneWidget);
    });

    testWidgets('reads as off even when the profile setting is on', (
      tester,
    ) async {
      await pumpTile(tester, makeViewModel(autocorrectOn: true), isWeb: true);

      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isFalse);
    });

    testWidgets('tapping shows a snackbar warning, backing off after 3 taps', (
      tester,
    ) async {
      final viewModel = makeViewModel();
      await pumpTile(tester, viewModel, isWeb: true);

      for (var i = 0; i < 3; i++) {
        await tapTile(tester);
        expect(find.text(snackBarWarning), findsOneWidget);
        await dismissSnackBar(tester);
        expect(find.text(snackBarWarning), findsNothing);
      }

      await tapTile(tester);
      expect(find.text(snackBarWarning), findsNothing);

      // The tap never toggles the setting.
      expect(viewModel.getToolSetting(ToolSetting.enableAutocorrect), isFalse);
    });
  });

  group('on mobile', () {
    testWidgets('switch is enabled with the standard description', (
      tester,
    ) async {
      await pumpTile(tester, makeViewModel(autocorrectOn: true), isWeb: false);

      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.onChanged, isNotNull);
      // The off-masking is web-only: on mobile the switch shows the setting.
      expect(tile.value, isTrue);
      expect(find.text(mobileOnlyLabel), findsNothing);
    });

    testWidgets('enabling shows the instructions dialog, then applies', (
      tester,
    ) async {
      final viewModel = makeViewModel();
      await pumpTile(tester, viewModel, isWeb: false);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      // Test VM is neither web nor iOS, so the Android dialog appears.
      expect(find.byType(AndroidEnableAutocorrectDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(viewModel.getToolSetting(ToolSetting.enableAutocorrect), isTrue);
    });
  });
}
