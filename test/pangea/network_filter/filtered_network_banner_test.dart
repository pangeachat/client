import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/network_filter/filtered_network_controller.dart';
import 'package:fluffychat/features/network_filter/network_host_category.dart';
import 'package:fluffychat/features/network_filter/widgets/filtered_network_banner.dart';
import 'package:fluffychat/features/network_filter/widgets/filtered_network_dialog.dart';
import 'package:fluffychat/features/network_filter/widgets/filtered_network_note.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// #9434 — what the user sees when the network blocks a host.
void main() {
  final blocked = FilteredNetworkController.instance.blocked;
  const bannerText = 'This network is blocking Pangea Chat';

  tearDown(() => FilteredNetworkController.instance.resetForTest());

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    builder: (context, child) => FilteredNetworkBanner(child: child),
    home: Scaffold(body: home),
  );

  Future<void> block(
    WidgetTester tester,
    Set<NetworkHostCategory> categories,
  ) async {
    blocked.value = categories;
    await tester.pump();
  }

  group('the banner', () {
    testWidgets('shows when the chat server or the Pangea API is blocked', (
      tester,
    ) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      expect(find.text(bannerText), findsNothing);

      await block(tester, {NetworkHostCategory.pangeaApi});
      expect(find.text(bannerText), findsOneWidget);
    });

    testWidgets('steps aside while the guidance it opens is showing', (
      tester,
    ) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await block(tester, {NetworkHostCategory.chatServer});

      FilteredNetworkDialog.isShowing.value = true;
      await tester.pump();
      expect(find.text(bannerText), findsNothing);

      FilteredNetworkDialog.isShowing.value = false;
      await tester.pump();
      expect(find.text(bannerText), findsOneWidget);
    });

    testWidgets('does not show for a block that breaks one feature', (
      tester,
    ) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await block(tester, {NetworkHostCategory.video, NetworkHostCategory.map});

      expect(find.text(bannerText), findsNothing);
    });

    testWidgets(
      'once dismissed, comes back only when another host is blocked',
      (tester) async {
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await block(tester, {NetworkHostCategory.chatServer});
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pump();
        expect(find.text(bannerText), findsNothing);

        await block(tester, {
          NetworkHostCategory.chatServer,
          NetworkHostCategory.video,
        });
        expect(find.text(bannerText), findsNothing);

        await block(tester, {
          NetworkHostCategory.chatServer,
          NetworkHostCategory.pangeaApi,
        });
        expect(find.text(bannerText), findsOneWidget);
      },
    );

    testWidgets(
      'once dismissed, comes back after the block clears and returns',
      (tester) async {
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await block(tester, {NetworkHostCategory.chatServer});
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pump();

        await block(tester, {});
        await block(tester, {NetworkHostCategory.chatServer});
        expect(find.text(bannerText), findsOneWidget);
      },
    );
  });

  testWidgets('a note takes a blocked feature\'s place, and only its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Column(
          children: [
            Expanded(
              child: FilteredNetworkNote(
                category: NetworkHostCategory.video,
                child: Text('player'),
              ),
            ),
            FilteredNetworkNote(category: NetworkHostCategory.map),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('player'), findsOneWidget);

    await block(tester, {NetworkHostCategory.video});
    expect(find.text('player'), findsNothing);
    expect(find.text('This network blocks videos.'), findsOneWidget);
    expect(find.text('This network blocks the map.'), findsNothing);
  });
}
