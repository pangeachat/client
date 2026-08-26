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

  /// Resolving a step spans several sequential awaits — both store
  /// hydrations, then the platform channel — and each needs the fake-async
  /// zone's microtask queue drained again before the next one resumes. One
  /// pumpAndSettle does not get far enough down that chain, so the banner
  /// reads as un-rendered while it is really still mid-resolve. Bounded so a
  /// genuinely stuck future still fails the test rather than hanging.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(Duration.zero);
    }
    await tester.pumpAndSettle();
  }

  /// Returns the composer's FocusNode so tests can drive focus loss, and the
  /// language holder so tests can change target language mid-flight.
  Future<(FocusNode, ValueNotifier<String?>)> pumpBanner(
    WidgetTester tester, {
    required String targetLanguageCode,
    required bool hasFocus,
  }) async {
    final focusNode = FocusNode();
    final language = ValueNotifier<String?>(targetLanguageCode);
    addTearDown(focusNode.dispose);
    addTearDown(language.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              // Rebuilt on language change so didUpdateWidget fires, the way
              // the real ChatInputBar rebuilds the banner from its parent.
              ValueListenableBuilder<String?>(
                valueListenable: language,
                builder: (context, value, _) => KeyboardPromptBanner(
                  composerFocusNode: focusNode,
                  targetLanguageCode: () => value,
                ),
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
    await settle(tester);
    return (focusNode, language);
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
    await settle(tester);
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
        await settle(tester);

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
      await settle(tester);

      expect(find.text(switchKeyboardMessage), findsOneWidget);
      expect(ObservedKeyboardStore.hasObservedKeyboard('es'), isFalse);
      // The poll timer is still running (no match yet) — unmount so
      // disposal cancels it before the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // Detection is advisory: a device we cannot read must produce silence. On
  // iOS this is the trap, because "assume equipped" lands on the
  // switch-keyboard step rather than on no prompt at all.
  testWidgets('stays silent on iOS when detection reports nothing usable', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      // No mock handler at all — the plugin call fails and reports no tags.
      await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);
      expect(find.text(addKeyboardMessage), findsNothing);
      expect(find.text(switchKeyboardMessage), findsNothing);
    });
  });

  testWidgets('clears the prompt and stops polling when focus is lost', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      mockChannel(enabledTags: ['es-MX'], currentInputMode: 'en-US');
      final (focusNode, _) = await pumpBanner(
        tester,
        targetLanguageCode: 'es',
        hasFocus: true,
      );
      expect(find.text(switchKeyboardMessage), findsOneWidget);

      focusNode.unfocus();
      await settle(tester);
      expect(find.text(switchKeyboardMessage), findsNothing);

      // Polling stopped with it: a tick that would otherwise observe a match
      // must not run while the composer is unfocused.
      mockChannel(enabledTags: ['es-MX'], currentInputMode: 'es-MX');
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(ObservedKeyboardStore.hasObservedKeyboard('es'), isFalse);
    });
  });

  testWidgets('a resume while unfocused does not surface the prompt', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      mockChannel(enabledTags: ['en-US']);
      await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: false);
      expect(find.text(addKeyboardMessage), findsNothing);

      // didChangeAppLifecycleState fires for every resume, focused or not.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(find.text(addKeyboardMessage), findsNothing);
    });
  });

  // The banner awaits store hydration before resolving; without that, a
  // cold-start read finds an empty set and re-shows a prompt the learner
  // already dismissed.
  testWidgets('a dismissed prompt does not reappear on a cold start', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'keyboard_prompt_dismissed_steps': ['addKeyboard:es'],
    });
    ObservedKeyboardStore.resetForTesting();
    KeyboardPromptDismissalStore.resetForTesting();

    mockChannel(enabledTags: ['en-US']);
    await pumpBanner(tester, targetLanguageCode: 'es', hasFocus: true);

    expect(find.text(addKeyboardMessage), findsNothing);
  });

  testWidgets('a stale poll cannot clear the step for a new target language', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      // Spanish is equipped-but-unobserved, so the switch step shows and
      // polls; the live keyboard already reads as Spanish, so the Spanish
      // tick would resolve if it were allowed to finish.
      mockChannel(enabledTags: ['es-MX', 'fr-FR'], currentInputMode: 'es-MX');
      final (_, language) = await pumpBanner(
        tester,
        targetLanguageCode: 'es',
        hasFocus: true,
      );
      expect(find.text(switchKeyboardMessage), findsOneWidget);

      // Fire the Spanish tick but do NOT settle: its callback is now
      // suspended at the platform-channel await, which is exactly the state
      // cancelling the timer cannot undo.
      await tester.pump(const Duration(seconds: 2));

      // Switch to French while that callback is parked. Resolving French
      // replaces the poll; the Spanish continuation must then do nothing.
      language.value = 'fr';
      await settle(tester);

      // French is still unobserved, so its step must stand. The Spanish
      // callback may legitimately have recorded Spanish as observed — the
      // tick was taken while Spanish really was the target — but it must not
      // clear the step that now belongs to French, which is what cancelling
      // the timer alone cannot prevent.
      expect(find.text(switchKeyboardMessage), findsOneWidget);
      expect(ObservedKeyboardStore.hasObservedKeyboard('fr'), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
