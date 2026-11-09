import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:url_launcher/link.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/notifications/suggest_mobile_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// #9684 — the web "get the app for notifications" dialog links to the app:
/// a computer gets a QR code plus both store badges, a phone browser gets
/// only its own store's badge.
void main() {
  const appStoreLabel = 'Download on the App Store';
  const googlePlayLabel = 'Get it on Google Play';

  setUpAll(() async {
    // The dialog's illustration is a CachedNetworkImage, whose cache manager
    // needs path_provider; stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('suggest_mobile');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
  });

  Future<L10n> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: Center(child: SuggestMobileDialog())),
      ),
    );
    await tester.pumpAndSettle();
    return L10n.of(tester.element(find.byType(SuggestMobileDialog)));
  }

  testWidgets(
    'a computer browser shows a QR code to the get-the-app link and both '
    'store badges, App Store first',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final l10n = await pumpDialog(tester);

      // The QR code takes the illustration's place.
      expect(find.byType(PrettyQrView), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('pangea.chat/app'), findsOneWidget);

      final appStore = find.bySemanticsLabel(appStoreLabel);
      final googlePlay = find.bySemanticsLabel(googlePlayLabel);
      // Name, focus and tap on one node. Its link role and URL come from
      // Link's web delegate, so they appear on web only.
      expect(
        tester.getSemantics(appStore),
        isSemantics(
          label: appStoreLabel,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(googlePlay),
        isSemantics(
          label: googlePlayLabel,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      // Each badge opens its listing in a new tab, so a click leaves this tab
      // on Pangea Chat (#9702).
      final links = tester.widgetList<Link>(find.byType(Link));
      expect(links.map((link) => link.uri), [
        Uri.parse(AppConfig.iosAppStoreURL),
        Uri.parse(AppConfig.androidUpdateURL),
      ]);
      expect(links.map((link) => link.target), everyElement(LinkTarget.blank));
      // The same height, as Google asks, and each holds its width before its
      // artwork has loaded.
      expect(tester.getSize(appStore).height, 40);
      expect(tester.getSize(appStore).width, closeTo(119.66, 0.01));
      expect(tester.getSize(googlePlay).height, 40);
      expect(tester.getSize(googlePlay).width, closeTo(134.29, 0.01));
      expect(
        tester.getTopLeft(appStore).dx,
        lessThan(tester.getTopLeft(googlePlay).dx),
      );
      expect(find.text(l10n.suggestMobileSignInSameAccount), findsOneWidget);
      semantics.dispose();
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'an iPhone browser shows the illustration and only the App Store badge, without a QR code',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final l10n = await pumpDialog(tester);

      expect(find.bySemanticsLabel(appStoreLabel), findsOneWidget);
      expect(find.bySemanticsLabel(googlePlayLabel), findsNothing);
      expect(find.byType(PrettyQrView), findsNothing);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text(l10n.suggestMobileSignInSameAccount), findsOneWidget);
      semantics.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'an Android browser shows the illustration and only the Google Play badge, without a QR code',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final l10n = await pumpDialog(tester);

      expect(find.bySemanticsLabel(googlePlayLabel), findsOneWidget);
      expect(find.bySemanticsLabel(appStoreLabel), findsNothing);
      expect(find.byType(PrettyQrView), findsNothing);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text(l10n.suggestMobileSignInSameAccount), findsOneWidget);
      semantics.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
