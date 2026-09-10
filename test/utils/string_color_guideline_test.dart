import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// #8762 — Flutter's own WCAG text-contrast guideline over the rendered
/// widgets: real fallback [Avatar]s (one per colour bucket) plus sender-name
/// and profile-name text styled as the timeline and profile paint them, on
/// the surface and on the darkest card, in both themes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One name per bucket: each name's code-unit sum % 12 equals its index.
  const bucketNames = [
    'H', 'I', 'J', 'K', 'L', 'A', // buckets 0–5
    'B', 'C', 'D', 'E', 'F', 'G', // buckets 6–11
  ];

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'string_color_guideline_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('svg_cache');
    // Avatar reads Environment.botName from dotenv.
    dotenv.testLoad(mergeWith: {'BOT_NAME': '@bot:example.com'});
  });

  Widget page(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppConfig.primaryColor,
      brightness: brightness,
    );
    Text nameText(String name, Color color) => Text(
      'Sender $name',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
    );
    return MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: Scaffold(
        body: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final name in bucketNames) Avatar(name: name),
            for (final name in bucketNames)
              nameText(name, name.timelineNameColor(brightness)),
            for (final name in bucketNames)
              nameText(name, name.profileNameColor(brightness)),
            ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Wrap(
                spacing: 4,
                children: [
                  for (final name in bucketNames)
                    nameText(name, name.timelineNameColor(brightness)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('palette meets textContrastGuideline — $brightness', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(page(brightness));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }
}
