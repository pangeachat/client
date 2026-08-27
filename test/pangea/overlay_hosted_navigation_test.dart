import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/subscription/widgets/unlock_button.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/message_unsubscribed_card.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

/// The word card is shown as an `OverlayEntry` — over a vocab chip on the
/// activity surfaces, over a message in chat. An entry sits BESIDE the route's
/// page in the Navigator's overlay, not under it, so `ModalRoute.of` finds
/// nothing there and `GoRouterState.of` throws. Every navigation the card
/// offers used to die on that throw inside an async tap handler, which is why
/// the buttons did nothing at all rather than reporting an error (#8622).
///
/// Read the current URI from the router instead. These tests pin that: they
/// mount each control in a real `OverlayEntry` and assert the URL moved.
void main() {
  /// Mounts [card] in an `OverlayEntry` over a route, the way the real word
  /// card is shown, and returns the router so a test can read the URL back.
  Future<GoRouter> pumpOverOverlay(WidgetTester tester, Widget card) async {
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (inner) => TextButton(
                onPressed: () => Overlay.of(inner).insert(
                  OverlayEntry(
                    builder: (_) =>
                        Align(alignment: Alignment.topLeft, child: card),
                  ),
                ),
                child: const Text('open card'),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
      ),
    );
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open card'));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('the unlock gate opens subscription settings', (tester) async {
    final router = await pumpOverOverlay(
      tester,
      MessageUnsubscribedCard(
        token: PangeaTokenText.fromString('Deutsch'),
        onClose: () {},
      ),
    );

    await tester.tap(find.byType(UnlockButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      contains('settingspage:subscription'),
    );
  });

  testWidgets('the word card opens its construct detail', (tester) async {
    final router = await pumpOverOverlay(
      tester,
      Material(
        child: Builder(
          builder: (cardContext) => TextButton(
            onPressed: () => AnalyticsNavigationUtil.navigateToAnalytics(
              context: cardContext,
              view: ProgressIndicatorEnum.wordsUsed,
              construct: ConstructIdentifier(
                lemma: 'hund',
                type: ConstructTypeEnum.vocab,
                category: 'NOUN',
              ),
            ),
            child: const Text('hund'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('hund'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      isNot('/rooms'),
      reason: 'the tap must move the workspace URL, not die silently',
    );
  });
}
