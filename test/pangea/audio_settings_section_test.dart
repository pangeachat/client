import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/audio_settings_section.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// #8117 — the Audio section of learning settings: voice dropdown plus the
/// three per-surface audio toggles (Words, Choices, Incoming messages).
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

  testWidgets('renders the section header, voice dropdown, and three toggles', (
    tester,
  ) async {
    await pumpSection(tester, makeViewModel());

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Pangea Bot audio message voice'), findsOneWidget);
    expect(find.text('Words'), findsOneWidget);
    expect(find.text('Choices'), findsOneWidget);
    expect(find.text('Incoming messages'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(3));

    // The retired toggles are gone.
    expect(find.text('Enabled text-to-speech'), findsNothing);
    expect(
      find.text('Automatically read aloud all received messages'),
      findsNothing,
    );
  });

  testWidgets('turning off the incoming messages toggle updates the view '
      'model', (tester) async {
    final viewModel = makeViewModel(
      toolSettings: const UserToolSettings(audioIncomingMessages: true),
    );
    await pumpSection(tester, viewModel);

    expect(viewModel.getToolSetting(ToolSetting.audioIncomingMessages), isTrue);

    // Disabling is ungated (the known-good-voice gate only guards enabling).
    await tester.tap(find.text('Incoming messages'));
    await tester.pumpAndSettle();

    expect(
      viewModel.getToolSetting(ToolSetting.audioIncomingMessages),
      isFalse,
    );
  });

  testWidgets('enabling incoming messages without a target language is '
      'blocked by the voice gate', (tester) async {
    final viewModel = makeViewModel();
    await pumpSection(tester, viewModel);

    await tester.tap(find.text('Incoming messages'));
    await tester.pumpAndSettle();

    expect(
      viewModel.getToolSetting(ToolSetting.audioIncomingMessages),
      isFalse,
    );
  });
}
