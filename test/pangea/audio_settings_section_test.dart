import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/audio_settings_section.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/read_aloud_voice_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// #8117 / #8264 / #8326 — the Audio section of learning settings: the
/// per-surface audio toggles (Words, Choices, On new message, On message
/// click), and the known-good-voice gate on the two message toggles.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');

  /// The voices `flutter_tts.getVoices` reports for the next engine query.
  /// `enhanced` clears the quality bar; `default` does not.
  List<Map<String, String>> deviceVoices = [];

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
  });

  setUp(() {
    deviceVoices = [
      {'name': 'Mónica (Enhanced)', 'locale': 'es-ES', 'quality': 'enhanced'},
    ];
  });

  LearningSettingsViewModel makeViewModel({
    UserToolSettings toolSettings = const UserToolSettings(),
  }) => LearningSettingsViewModel(
    Profile(
      userSettings: UserSettings(sourceLanguage: 'en', targetLanguage: 'es'),
      toolSettings: toolSettings,
    ),
  );

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
            child: AudioSettingsSection(viewModel: viewModel),
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

    // The retired single message-audio toggle is gone (#8264).
    expect(find.text('Incoming messages'), findsNothing);
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

  testWidgets('enabling a message toggle without a known-good voice is '
      'blocked by the gate', (tester) async {
    deviceVoices = [
      {'name': 'Mónica', 'locale': 'es-ES', 'quality': 'default'},
    ];
    final viewModel = makeViewModel(
      toolSettings: const UserToolSettings(
        audioOnNewMessage: false,
        audioOnMessageClick: false,
      ),
    );
    await pumpSection(tester, viewModel);

    await tester.tap(find.text('On new message'));
    await tester.pumpAndSettle();

    expect(viewModel.getToolSetting(ToolSetting.audioOnNewMessage), isFalse);
    expect(find.byType(ReadAloudVoiceDialog), findsOneWidget);
  });

  testWidgets('a toggle stored on reads on once a qualifying voice is '
      'downloaded', (tester) async {
    deviceVoices = [
      {'name': 'Mónica', 'locale': 'es-ES', 'quality': 'default'},
    ];
    final viewModel = makeViewModel();
    await pumpSection(tester, viewModel);
    expect(viewModel.getToolSetting(ToolSetting.audioOnMessageClick), isFalse);

    // The learner follows the dialog to system settings and comes back.
    deviceVoices = [
      {'name': 'Mónica (Enhanced)', 'locale': 'es-ES', 'quality': 'enhanced'},
    ];
    await tester.tap(find.text('On message click'));
    await tester.pumpAndSettle();

    expect(viewModel.getToolSetting(ToolSetting.audioOnMessageClick), isTrue);
    expect(find.byType(ReadAloudVoiceDialog), findsNothing);
  });
}
