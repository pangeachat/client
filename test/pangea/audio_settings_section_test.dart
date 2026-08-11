import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/audio_settings_section.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// #8117 / #8264 — the Audio section of learning settings: the per-surface
/// audio toggles (Words, Choices, On new message, On message click).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LearningSettingsViewModel makeViewModel({
    UserToolSettings toolSettings = const UserToolSettings(),
  }) => LearningSettingsViewModel(
    Profile(userSettings: UserSettings(), toolSettings: toolSettings),
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

  testWidgets('enabling a message toggle without a target language is '
      'blocked by the voice gate', (tester) async {
    final viewModel = makeViewModel(
      toolSettings: const UserToolSettings(
        audioOnNewMessage: false,
        audioOnMessageClick: false,
      ),
    );
    await pumpSection(tester, viewModel);

    await tester.tap(find.text('On new message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On message click'));
    await tester.pumpAndSettle();

    expect(viewModel.getToolSetting(ToolSetting.audioOnNewMessage), isFalse);
    expect(viewModel.getToolSetting(ToolSetting.audioOnMessageClick), isFalse);
  });
}
