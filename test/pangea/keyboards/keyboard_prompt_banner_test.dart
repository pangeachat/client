import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/keyboards/keyboard_prompt_local_store.dart';
import 'package:fluffychat/features/keyboards/keyboard_prompt_step.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/keyboard_prompt_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pangea/keyboard_languages');

  const addKeyboardMessage =
      'Add a keyboard for your target language so autocorrect works.';
  const switchKeyboardMessage =
      'Tap the globe icon on your keyboard to switch to your target language.';

  /// [enabledTags] backs getEnabledLanguageTags (the has-a-keyboard check);
  /// [currentInputMode] backs getCurrentInputModeLanguage (the live-poll
  /// check for the switch-keyboard step).
  void mockChannel({
    List<String> enabledTags = const [],
    String? currentInputMode,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getEnabledLanguageTags':
              return enabledTags;
            case 'getCurrentInputModeLanguage':
              return currentInputMode;
            default:
              return null;
          }
        });
  }

  Future<void> pumpBanner(
    WidgetTester tester, {
    required String targetLanguageCode,
    required bool hasFocus,
  }) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              KeyboardPromptBanner(
                composerFocusNode: focusNode,
                targetLanguageCode: () => targetLanguageCode,
              ),
              // A bare FocusNode never attaches to the focus tree, so
              // requestFocus() below is a no-op without a real focusable
              // consumer — mirrors how the composer's own TextField owns
              // this FocusNode in the real app.
              TextField(focusNode: focusNode),
            ],
          ),
        ),
      ),
    );
    if (hasFocus) focusNode.requestFocus();
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ObservedKeyboardStore.initialize();
    await KeyboardPromptDismissalStore.initialize();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // The widget-binding invariant check runs before tearDowns do, so a
  // platform override has to be reset inside the test body itself (matches
  // the same pattern in autocorrect_settings_tile_test.dart).
  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('shows nothing before the composer is focused', (tester) async {
    mockChannel();
    await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: false);
    expect(find.text(addKeyboardMessage), findsNothing);
  });

  testWidgets('shows the add-keyboard step when nothing matches', (
    tester,
  ) async {
    mockChannel(enabledTags: ['en-US']);
    await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
    expect(find.text(addKeyboardMessage), findsOneWidget);
  });

  testWidgets('shows nothing on Android once the language matches', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.android, () async {
      mockChannel(enabledTags: ['es-MX']);
      await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
      expect(find.text(addKeyboardMessage), findsNothing);
      expect(find.text(switchKeyboardMessage), findsNothing);
    });
  });

  testWidgets(
    'shows the switch-keyboard step on iOS when equipped but unobserved',
    (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        mockChannel(enabledTags: ['es-MX']);
        await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
        expect(find.text(switchKeyboardMessage), findsOneWidget);
        // This step polls in the background — unmount so disposal cancels
        // that timer before the test ends.
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );

  testWidgets('shows nothing on iOS once the language has been observed', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      await ObservedKeyboardStore.markObserved('es');
      mockChannel(enabledTags: ['es-MX']);
      await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
      expect(find.text(switchKeyboardMessage), findsNothing);
    });
  });

  testWidgets('dismissing the add-keyboard step hides it and persists', (
    tester,
  ) async {
    mockChannel(enabledTags: ['en-US']);
    await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
    expect(find.text(addKeyboardMessage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pumpAndSettle();
    expect(find.text(addKeyboardMessage), findsNothing);

    expect(
      KeyboardPromptDismissalStore.isDismissed(
        KeyboardPromptStep.addKeyboard,
        'es',
      ),
      isTrue,
    );
  });

  testWidgets('a dismissed step stays hidden across a fresh mount', (
    tester,
  ) async {
    await KeyboardPromptDismissalStore.dismiss(
      KeyboardPromptStep.addKeyboard,
      'es',
    );
    mockChannel(enabledTags: ['en-US']);
    await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
    expect(find.text(addKeyboardMessage), findsNothing);
  });

  testWidgets(
    'polling the live keyboard mode clears the switch-keyboard step on a match',
    (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        mockChannel(enabledTags: ['es-MX'], currentInputMode: 'en-US');
        await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
        expect(find.text(switchKeyboardMessage), findsOneWidget);

        // The learner switches keyboards mid-session; the next poll tick
        // sees it.
        mockChannel(enabledTags: ['es-MX'], currentInputMode: 'es-MX');
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(find.text(switchKeyboardMessage), findsNothing);
        expect(ObservedKeyboardStore.hasObservedKeyboard('es'), isTrue);
        // The poll timer is cancelled once it observes a match, so nothing
        // is left pending — unmount to confirm rather than assume.
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );

  testWidgets('a mismatched live keyboard mode does not clear the step', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      mockChannel(enabledTags: ['es-MX'], currentInputMode: 'fr-FR');
      await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
      expect(find.text(switchKeyboardMessage), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text(switchKeyboardMessage), findsOneWidget);
      expect(ObservedKeyboardStore.hasObservedKeyboard('es'), isFalse);
      // The poll timer is still running (no match yet) — unmount so
      // disposal cancels it before the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
