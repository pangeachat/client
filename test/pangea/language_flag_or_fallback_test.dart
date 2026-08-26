import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/languages/language_flag_chip.dart';
import 'package:fluffychat/features/languages/language_flag_or_fallback.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/utils/svg_repo.dart';

/// With no connection a flag SVG never arrives, and the surfaces that draw one
/// used to show a broken flag rather than their own no-flag appearance: the
/// language switcher drew a squished two-letter badge where every other row
/// had a circle, the learning-settings chip drew its language code twice and
/// off-centre from itself, and a name whose flag never came still reserved the
/// hole it would have filled (#8548).
///
/// What's pinned here: a flag that can't be fetched hands the surface back to
/// the fallback it was given, whatever shape that is; a flag that can be
/// fetched still wins; and a flag already known to be missing is missing from
/// the first frame, so a list scrolling by doesn't flash between the two.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // GetStorage needs path_provider; stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('flag_fallback_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('svg_cache');
  });

  const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>';

  // SvgRepo memoizes by URL for the life of the session, so each case needs a
  // language no other case has used.
  var langCounter = 0;
  LanguageModel freshLanguage() =>
      LanguageModel(langCode: 'zz${langCounter++}', displayName: 'Testish');

  Future<http.Response> serveFlag(http.Request _) async =>
      http.Response(svg, 200);

  Future<http.Response> failToServeFlag(http.Request _) async =>
      throw http.ClientException('Failed to fetch');

  /// Mounts [child] and lets the flag fetch actually run. It reaches the
  /// filesystem (the SVG cache) and the mock client, neither of which the
  /// widget tester's fake clock will advance — hence [WidgetTester.runAsync].
  Future<void> mountAndLoad(
    WidgetTester tester,
    Widget child,
    LanguageModel language,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    await tester.runAsync(() async {
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: child));

        // The widget awaits this exact memoized future.
        await SvgRepo.get(language.svgUrl.toString());
        await Future<void>.delayed(Duration.zero);
      }, () => MockClient(handler));
    });
    await tester.pump();
  }

  group('LanguageFlagOrFallback', () {
    testWidgets('a flag that cannot be fetched gives way to the fallback', (
      tester,
    ) async {
      final language = freshLanguage();
      await mountAndLoad(
        tester,
        LanguageFlagOrFallback(
          language: language,
          flag: const Text('flag'),
          fallback: const Text('fallback'),
        ),
        language,
        failToServeFlag,
      );

      expect(find.text('fallback'), findsOneWidget);
      expect(find.text('flag'), findsNothing);
    });

    testWidgets('a flag that loads keeps its place', (tester) async {
      final language = freshLanguage();
      await mountAndLoad(
        tester,
        LanguageFlagOrFallback(
          language: language,
          flag: const Text('flag'),
          fallback: const Text('fallback'),
        ),
        language,
        serveFlag,
      );

      expect(find.text('flag'), findsOneWidget);
      expect(find.text('fallback'), findsNothing);
    });

    testWidgets('a flag already known to be missing never flashes in', (
      tester,
    ) async {
      final language = freshLanguage();
      await mountAndLoad(
        tester,
        LanguageFlagOrFallback(
          language: language,
          flag: const Text('flag'),
          fallback: const Text('fallback'),
        ),
        language,
        failToServeFlag,
      );

      // A second row for the same language, built from scratch the way one
      // scrolling back into view is.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
          home: LanguageFlagOrFallback(
            language: language,
            flag: const Text('flag'),
            fallback: const Text('fallback'),
          ),
        ),
      );

      // No settling: this is the first frame the new widget ever drew.
      expect(find.text('fallback'), findsOneWidget);
      expect(find.text('flag'), findsNothing);
    });
  });

  group('LanguageFlagChip', () {
    testWidgets('a flag that cannot be fetched leaves one language code', (
      tester,
    ) async {
      final language = freshLanguage();
      await mountAndLoad(
        tester,
        LanguageFlagChip(language: language, langCode: language.langCode),
        language,
        failToServeFlag,
      );

      // The code is drawn twice by design — an outline pass under a fill pass.
      // Four is the defect: the flag's own fallback landing under the code
      // already overlaid on it, each in a different place (#8548).
      expect(find.text(language.langCode.toUpperCase()), findsNWidgets(2));
    });
  });
}
