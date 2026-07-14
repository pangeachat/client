import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/l10n/l10n.dart';

void main() {
  // The currency logic lives in the context-free `formattedPrice()` so it is
  // unit-testable without an L10n BuildContext; `displayPrice` layers the trial
  // copy on top (covered by the widget group below).
  group('SubscriptionDetails.formattedPrice (D5, currency-aware)', () {
    test('usd formats with a "\$" symbol', () {
      final details = SubscriptionDetails(
        id: "month",
        price: 9.99,
        currency: "usd",
      );
      expect(details.formattedPrice(), "\$9.99");
    });

    test('a non-usd currency formats WITHOUT a "\$"', () {
      final details = SubscriptionDetails(
        id: "month",
        price: 9.99,
        currency: "eur",
      );
      final formatted = details.formattedPrice();
      expect(formatted, isNot(contains("\$")));
      expect(formatted, contains("9.99"));
    });

    test('localizedPrice wins over currency formatting', () {
      final details = SubscriptionDetails(
        id: "month",
        price: 9.99,
        currency: "usd",
        localizedPrice: "US\$9.99",
      );
      expect(details.formattedPrice(), "US\$9.99");
    });

    test(
      'mobile (currency == null) is byte-for-byte the prior "\$" fallback',
      () {
        final details = SubscriptionDetails(id: "month", price: 9.99);
        expect(details.formattedPrice(), "\$9.99");
      },
    );

    test('mobile (currency == null) keeps localizedPrice precedence', () {
      final details = SubscriptionDetails(
        id: "month",
        price: 9.99,
        localizedPrice: "R\$9,99",
      );
      expect(details.formattedPrice(), "R\$9,99");
    });
  });

  group('SubscriptionDetails.displayPrice (L10n context)', () {
    late L10n l10n;

    Future<void> captureL10n(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = L10n.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('priced usd product renders the currency-formatted price', (
      tester,
    ) async {
      String? rendered;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) {
              rendered = SubscriptionDetails(
                id: "month",
                price: 9.99,
                currency: "usd",
              ).displayPrice(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(rendered, "\$9.99");
    });

    testWidgets('trial / zero-price product renders the freeTrial copy', (
      tester,
    ) async {
      await captureL10n(tester);
      String? trialRendered;
      String? zeroRendered;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) {
              trialRendered = SubscriptionDetails(
                id: "trial",
                price: 0,
                appId: "trial",
              ).displayPrice(context);
              zeroRendered = SubscriptionDetails(
                id: "comp",
                price: 0,
                currency: "usd",
              ).displayPrice(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(trialRendered, l10n.freeTrial);
      expect(zeroRendered, l10n.freeTrial);
    });
  });
}
