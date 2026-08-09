import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/preset_avatars.dart';
import 'package:fluffychat/pangea/common/widgets/preset_avatar_picker.dart';

/// #8111 — existing users can re-pick a preset Pangea avatar from the
/// profile page. Covers the shared preset row (also used in onboarding)
/// and the picker dialog opened from the change-avatar popup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // ImageByUrl reads Environment.cmsApi, which needs dotenv to be
    // readable; setting CMS_API also keeps it off the GetStorage-backed
    // appConfigOverride path. The image cache manager needs path_provider.
    final tempDir = await Directory.systemTemp.createTemp(
      'preset_avatar_picker',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.example'});
  });

  // The L10n delegates load asynchronously, so the localized subtree is
  // empty for the first pumped frame — pump extra frames after building.
  Future<void> settleL10n(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpRow(
    WidgetTester tester,
    void Function(Uri) onSelected,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: PresetAvatarRow(onSelected: onSelected)),
      ),
    );
    await settleL10n(tester);
  }

  testWidgets('shows one labeled button per preset avatar', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRow(tester, (_) {});

    expect(
      find.descendant(
        of: find.byType(PresetAvatarRow),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(PresetAvatars.count),
    );
    for (final label in [
      'A dinosaur with sunglasses',
      'A friendly bear',
      'A squid wearing headphones',
      'A happy cartoon character waving',
      'A robot with stars for eyes',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('tapping a preset delivers its URL', (tester) async {
    Uri? selected;
    await pumpRow(tester, (url) => selected = url);

    await tester.tap(
      find
          .descendant(
            of: find.byType(PresetAvatarRow),
            matching: find.byType(InkWell),
          )
          .at(2),
    );
    expect(selected, PresetAvatars.url(3));
  });

  group('showPresetAvatarPickerDialog', () {
    Future<void> pumpDialogOpener(
      WidgetTester tester,
      void Function(Uri?) onResult,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    onResult(await showPresetAvatarPickerDialog(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await settleL10n(tester);
    }

    testWidgets('selection resolves to the chosen preset URL', (tester) async {
      Uri? result;
      await pumpDialogOpener(tester, (url) => result = url);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Choose a Pangea avatar'), findsOneWidget);

      await tester.tap(
        find
            .descendant(
              of: find.byType(PresetAvatarRow),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(result, PresetAvatars.url(1));
      expect(find.text('Choose a Pangea avatar'), findsNothing);
    });

    testWidgets('cancel resolves to null', (tester) async {
      Uri? result = PresetAvatars.url(1);
      await pumpDialogOpener(tester, (url) => result = url);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(result, isNull);
      expect(find.text('Choose a Pangea avatar'), findsNothing);
    });
  });
}
