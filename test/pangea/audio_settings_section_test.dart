import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/audio_settings_section.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/read_aloud_voice_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// Keeps the profile in memory instead of reading Matrix account data, so a
/// test can push a synced profile the way an account data sync would.
class _StubUserController extends UserController {
  _StubUserController(this.syncedProfile);

  Profile syncedProfile;

  @override
  Profile get profile => syncedProfile;

  /// What [UserController._onProfileUpdate] does when account data changes:
  /// swap the cached profile, then announce it.
  void sync(Profile updated) {
    syncedProfile = updated;
    settingsUpdateStream.add(updated);
  }
}

/// #8117 / #8264 / #8326 / #8334 / #8664 — the Audio section of learning
/// settings: the per-surface audio toggles (Words, Choices, On new message, On
/// message click), the known-good-voice gate on the two message toggles — which
/// renders them disabled with an explanatory subtitle when it fails — and
/// keeping all of them current with profile changes made off this page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');

  /// The voices `flutter_tts.getVoices` reports for the next engine query.
  /// `enhanced` clears the quality bar; `default` does not.
  List<Map<String, String>> deviceVoices = [];

  late Client client;
  late _StubUserController userController;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
          if (call.method == 'getVoices') return deviceVoices;
          return 1;
        });

    // The target language resolves through PLanguageStore, so seed its cache
    // rather than letting initialize() reach the network.
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
        ],
      }),
    });
    await PLanguageStore.initialize();

    // The view model listens to the user controller's profile streams, so it
    // needs a controller to reach through MatrixState.
    client = await prepareTestClient();
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
  });

  tearDownAll(() => client.dispose());

  setUp(() {
    deviceVoices = [
      {'name': 'Mónica (Enhanced)', 'locale': 'es-ES', 'quality': 'enhanced'},
    ];
  });

  LearningSettingsViewModel makeViewModel({
    UserToolSettings toolSettings = const UserToolSettings(),
  }) {
    final profile = Profile(
      userSettings: UserSettings(sourceLanguage: 'en', targetLanguage: 'es'),
      toolSettings: toolSettings,
    );
    // Swapped in per test so each one starts from its own profile, and so the
    // PangeaController's own subscriptions stay on the controller it built.
    userController = _StubUserController(profile);
    MatrixState.pangeaController.userController = userController;
    return LearningSettingsViewModel(profile);
  }

  bool toggleValue(WidgetTester tester, String title) => tester
      .widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      )
      .value;

  Future<void> pumpSection(
    WidgetTester tester,
    LearningSettingsViewModel viewModel,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            // The section redraws off the view model through the same
            // ListenableBuilder LearningSettingsTiles mounts it under.
            child: ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) =>
                  AudioSettingsSection(viewModel: viewModel),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the section header and four toggles', (tester) async {
    await pumpSection(tester, makeViewModel());

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Words'), findsOneWidget);
    expect(find.text('Choices'), findsOneWidget);
    expect(find.text('On new message'), findsOneWidget);
    expect(find.text('On message click'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(4));

    // The retired single message-audio toggle is gone (#8264), and the
    // no-voice note only renders when the gate fails (#8664).
    expect(find.text('Incoming messages'), findsNothing);
    expect(find.textContaining('message toolbar'), findsNothing);
  });

  testWidgets('turning off the message toggles updates the view model', (
    tester,
  ) async {
    final viewModel = makeViewModel();
    await pumpSection(tester, viewModel);

    expect(viewModel.getToolSetting(ToolSetting.audioOnNewMessage), isTrue);
    expect(viewModel.getToolSetting(ToolSetting.audioOnMessageClick), isTrue);

    // Disabling is ungated (the known-good-voice gate only guards enabling).
    await tester.tap(find.text('On new message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On message click'));
    await tester.pumpAndSettle();

    expect(viewModel.getToolSetting(ToolSetting.audioOnNewMessage), isFalse);
    expect(viewModel.getToolSetting(ToolSetting.audioOnMessageClick), isFalse);
  });

  testWidgets('the message toggles read off without a known-good voice, '
      'whatever the account setting says (#8326)', (tester) async {
    deviceVoices = [
      {'name': 'Mónica', 'locale': 'es-ES', 'quality': 'default'},
    ];
    // Both stored on — the default every account starts with (#8264).
    final viewModel = makeViewModel();
    await pumpSection(tester, viewModel);

    expect(viewModel.getToolSetting(ToolSetting.audioOnNewMessage), isFalse);
    expect(viewModel.getToolSetting(ToolSetting.audioOnMessageClick), isFalse);
  });

  testWidgets('without a known-good voice the message toggles are disabled, '
      'with one explanatory note above them (#8664)', (tester) async {
    deviceVoices = [
      {'name': 'Mónica', 'locale': 'es-ES', 'quality': 'default'},
    ];
    final viewModel = makeViewModel();
    await pumpSection(tester, viewModel);

    for (final title in ['On new message', 'On message click']) {
      final tile = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
    }
    // One shared note above the two tiles, which keep their own descriptions.
    expect(
      find.textContaining('No high-quality Spanish voice'),
      findsOneWidget,
    );
    expect(
      find.textContaining('play audio from the message toolbar'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Automatically read new received messages'),
      findsOneWidget,
    );

    // A tap on a disabled toggle changes nothing and opens nothing.
    await tester.tap(find.text('On new message'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadAloudVoiceDialog), findsNothing);

    // The word and choice toggles answer a different gate and stay live.
    for (final title in ['Words', 'Choices']) {
      final tile = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(tile.onChanged, isNotNull);
    }
  });

  testWidgets('a toggle stored on reads enabled and on when a later visit '
      'finds a qualifying voice', (tester) async {
    deviceVoices = [
      {'name': 'Mónica', 'locale': 'es-ES', 'quality': 'default'},
    ];
    await pumpSection(tester, makeViewModel());
    expect(toggleValue(tester, 'On message click'), isFalse);

    // The learner downloads an Enhanced voice and reopens the page — a
    // disabled toggle takes no taps, so re-entry is what re-runs the gate.
    deviceVoices = [
      {'name': 'Mónica (Enhanced)', 'locale': 'es-ES', 'quality': 'enhanced'},
    ];
    final viewModel = makeViewModel();
    await pumpSection(tester, viewModel);
    await viewModel.refreshKnownGoodVoice();
    await tester.pumpAndSettle();

    expect(viewModel.getToolSetting(ToolSetting.audioOnMessageClick), isTrue);
    expect(toggleValue(tester, 'On message click'), isTrue);
  });

  testWidgets('an enabled toggle whose tap-time re-check fails shows the '
      'voice dialog and the toggles fall back to disabled', (tester) async {
    // A qualifying voice at page open, gone by the time the learner taps —
    // the stale-answer case the tap-time re-check exists for (#8282).
    final viewModel = makeViewModel(
      toolSettings: const UserToolSettings(audioOnNewMessage: false),
    );
    await pumpSection(tester, viewModel);

    deviceVoices = [
      {'name': 'Mónica', 'locale': 'es-ES', 'quality': 'default'},
    ];
    await tester.tap(find.text('On new message'));
    await tester.pumpAndSettle();

    expect(viewModel.getToolSetting(ToolSetting.audioOnNewMessage), isFalse);
    expect(find.byType(ReadAloudVoiceDialog), findsOneWidget);
    final tile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('On new message'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(tile.onChanged, isNull);
  });

  testWidgets('a toggle turned on elsewhere reads on here (#8334)', (
    tester,
  ) async {
    final viewModel = makeViewModel(
      toolSettings: const UserToolSettings(audioWords: false),
    );
    await pumpSection(tester, viewModel);
    expect(toggleValue(tester, 'Words'), isFalse);

    // What the word card's "enable audio" prompt writes, coming back on sync
    // while this page is open beside the chat.
    userController.sync(
      viewModel.updatedProfile.copyWith(
        toolSettings: viewModel.updatedProfile.toolSettings.copyWith(
          audioWords: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(viewModel.getToolSetting(ToolSetting.audioWords), isTrue);
    expect(toggleValue(tester, 'Words'), isTrue);
  });
}
