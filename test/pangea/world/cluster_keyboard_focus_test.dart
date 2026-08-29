import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';

/// Covers #7219's cluster half: the Settings avatar and the language flag were
/// bare GestureDetectors — no focus node at all — so the expected tab ring
/// (… → Settings → Analytics) could never reach Settings or Learning settings
/// regardless of traversal order. They are now [FocusRingTapTarget]s: Tab
/// reaches them, a gold focus ring appears (their fills are opaque, so
/// InkWell's behind-the-child highlight alone is invisible), and Enter
/// activates them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The flag chip's NetworkSvg caches through GetStorage, which needs
    // path_provider; stub the channel to a temp dir. (The SVG fetch itself
    // fails in tests and the chip renders its fallback — fine here.)
    final tempDir = await Directory.systemTemp.createTemp('cluster_focus_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('svg_cache');
    // Avatar reads Environment.botName from dotenv.
    dotenv.testLoad(mergeWith: {'BOT_NAME': '@bot:example.com'});
  });

  /// Whether [root]'s subtree currently paints the gold focus ring (the
  /// 3px-side ShapeDecoration the [FocusRingTapTarget] draws while focused).
  bool showsFocusRing(WidgetTester tester, Finder root) {
    return tester
        .widgetList<DecoratedBox>(
          find.descendant(of: root, matching: find.byType(DecoratedBox)),
        )
        .any((box) {
          final decoration = box.decoration;
          return decoration is ShapeDecoration &&
              decoration.shape is OutlinedBorder &&
              (decoration.shape as OutlinedBorder).side.width == 3.0;
        });
  }

  testWidgets(
    'Tab reaches the avatar and the flag; the ring shows; Enter activates',
    (tester) async {
      var avatarOpened = 0;
      var flagOpened = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                ClusterAvatar(
                  avatarUrl: null,
                  name: 'Test User',
                  onTap: () => avatarOpened++,
                ),
                ClusterLanguageFlag(
                  language: LanguageModel(
                    langCode: 'es',
                    displayName: 'Spanish',
                  ),
                  onTap: () => flagOpened++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final avatar = find.byType(ClusterAvatar);
      final flag = find.byType(ClusterLanguageFlag);
      expect(showsFocusRing(tester, avatar), isFalse);

      // First Tab: the Settings avatar.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        showsFocusRing(tester, avatar),
        isTrue,
        reason:
            'one Tab must focus the Settings avatar with a visible ring '
            '(#7219 — it was a bare GestureDetector, unreachable by keyboard)',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        avatarOpened,
        1,
        reason: 'Enter on the focused avatar must open Settings',
      );

      // Second Tab: the language flag.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        showsFocusRing(tester, avatar),
        isFalse,
        reason: 'the ring must follow focus off the avatar',
      );
      expect(
        showsFocusRing(tester, flag),
        isTrue,
        reason: 'the second Tab must focus the language flag with its ring',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        flagOpened,
        1,
        reason: 'Enter on the focused flag must open Learning settings',
      );
    },
  );
}
