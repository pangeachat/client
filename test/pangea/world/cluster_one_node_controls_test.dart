import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import '../one_node_control.dart';

/// #8873 — each of the cluster's three ring-backed controls is one semantics
/// node carrying name, role, focus and tap. Before: the avatar and the flag
/// chip were named buttons that were not focusable (no tabindex on web), and
/// the level medal was a roleless focusable wrapper over a named child.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('cluster_one_node');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('svg_cache');
    dotenv.testLoad(mergeWith: {'BOT_NAME': '@bot:example.com'});
  });

  testWidgets('avatar, level medal and flag chip are each one node', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              ClusterAvatar(avatarUrl: null, name: 'Test User', onTap: () {}),
              ClusterLevelMedal(level: 2, onTap: () {}),
              ClusterLanguageFlag(
                language: LanguageModel(langCode: 'es', displayName: 'Spanish'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = L10n.of(tester.element(find.byType(Scaffold)));

    expectOneNodeControl(tester, l10n.settings);
    expectOneNodeControl(tester, '${l10n.level} 2');
    expectOneNodeControl(tester, 'Spanish, ${l10n.learningSettings}');
  });
}
