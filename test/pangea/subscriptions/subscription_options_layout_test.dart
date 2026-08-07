import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_option_card.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_options.dart';

void main() {
  const plans = [
    ProductPlan(
      planId: 'month',
      amount: 999,
      currency: 'usd',
      interval: 'month',
      intervalCount: 1,
    ),
    ProductPlan(
      planId: 'year',
      amount: 9999,
      currency: 'usd',
      interval: 'year',
      intervalCount: 1,
    ),
  ];

  /// Pumps the plan picker inside a box [width] wide, the way the subscription
  /// page's max-400 card constrains it.
  Future<void> pumpOptions(
    WidgetTester tester, {
    double width = 368.0,
    ValueNotifier<ProductPlan?>? selected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SubscriptionOptionsInternal(
                plans,
                onEnterDiscountCode: () async {},
                onTapSubscription: (p) async => selected?.value = p,
                selectedSubscription: selected ?? ValueNotifier(null),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The discount-code button, as opposed to the chips — which are themselves
  /// [ElevatedButton]s.
  final discountButton = find.widgetWithText(
    ElevatedButton,
    'Enter discount code',
  );

  /// Elevation of the [Material] the first chip's button paints itself on.
  double chipElevation(WidgetTester tester) => tester
      .widget<Material>(
        find
            .descendant(
              of: find.byType(SubscriptionOptionCard).first,
              matching: find.byType(Material),
            )
            .first,
      )
      .elevation;

  group('discount-code button aligns with the plan chips', () {
    testWidgets('two chips per row: button spans both chips', (tester) async {
      await pumpOptions(tester);

      final wrapWidth = tester.getSize(find.byType(Wrap)).width;
      final buttonWidth = tester.getSize(discountButton).width;

      // 150 + 12 + 150
      expect(wrapWidth, 312.0);
      expect(buttonWidth, wrapWidth);
    });

    testWidgets('one chip per row: button matches the single chip', (
      tester,
    ) async {
      await pumpOptions(tester, width: 200.0);

      final wrapWidth = tester.getSize(find.byType(Wrap)).width;
      final buttonWidth = tester.getSize(discountButton).width;

      expect(wrapWidth, 150.0);
      expect(buttonWidth, wrapWidth);
    });
  });

  group('plan chips read as clickable', () {
    testWidgets('rests raised off the page', (tester) async {
      await pumpOptions(tester);

      expect(chipElevation(tester), greaterThan(0.0));
    });

    testWidgets('rises further on hover', (tester) async {
      await pumpOptions(tester);
      final resting = chipElevation(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();

      await mouse.moveTo(
        tester.getCenter(find.byType(SubscriptionOptionCard).first),
      );
      await tester.pumpAndSettle();

      expect(chipElevation(tester), greaterThan(resting));
    });

    testWidgets('selecting a plan still reports the tap', (tester) async {
      final selected = ValueNotifier<ProductPlan?>(null);
      await pumpOptions(tester, selected: selected);

      await tester.tap(find.byType(SubscriptionOptionCard).first);
      await tester.pumpAndSettle();

      expect(selected.value?.planId, 'month');
    });
  });
}
