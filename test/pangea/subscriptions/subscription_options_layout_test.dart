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
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: ThemeData(brightness: brightness),
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

  /// The card's outer [AnimatedContainer] — the one carrying the drop shadow
  /// and the hover lift.
  AnimatedContainer cardShell(WidgetTester tester) => tester.widget(
    find
        .descendant(
          of: find.byType(SubscriptionOptionCard).first,
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );

  BoxShadow cardShadow(WidgetTester tester) =>
      ((cardShell(tester).decoration! as BoxDecoration).boxShadow!).single;

  group('discount-code button aligns with the plan chips', () {
    testWidgets('two chips per row: button spans both chips', (tester) async {
      await pumpOptions(tester);

      final wrapWidth = tester.getSize(find.byType(Wrap)).width;
      final buttonWidth = tester.getSize(find.byType(ElevatedButton)).width;

      // 150 + 12 + 150
      expect(wrapWidth, 312.0);
      expect(buttonWidth, wrapWidth);
    });

    testWidgets('one chip per row: button matches the single chip', (
      tester,
    ) async {
      await pumpOptions(tester, width: 200.0);

      final wrapWidth = tester.getSize(find.byType(Wrap)).width;
      final buttonWidth = tester.getSize(find.byType(ElevatedButton)).width;

      expect(wrapWidth, 150.0);
      expect(buttonWidth, wrapWidth);
    });
  });

  group('plan chips read as clickable', () {
    testWidgets('rests with a drop shadow', (tester) async {
      await pumpOptions(tester);

      final shadow = cardShadow(tester);
      expect(shadow.blurRadius, 4.0);
      expect(shadow.offset, const Offset(0, 2));
      expect(
        cardShell(tester).transform,
        Matrix4.translationValues(0, 0, 0),
        reason: 'sits flush until hovered',
      );
    });

    testWidgets('lifts and deepens its shadow on hover', (tester) async {
      await pumpOptions(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();

      await mouse.moveTo(
        tester.getCenter(find.byType(SubscriptionOptionCard).first),
      );
      await tester.pumpAndSettle();

      final shadow = cardShadow(tester);
      expect(shadow.blurRadius, 10.0);
      expect(shadow.offset, const Offset(0, 4));
      expect(
        cardShell(tester).transform,
        Matrix4.translationValues(0, -2, 0),
        reason: 'lifts toward the pointer',
      );
    });

    testWidgets('casts a visible glow instead of a black shadow in the dark', (
      tester,
    ) async {
      await pumpOptions(tester, brightness: Brightness.dark);

      final theme = ThemeData(brightness: Brightness.dark);
      final shadow = cardShadow(tester);

      // Black-on-near-black would read as no elevation at all.
      expect(shadow.color.withAlpha(255), theme.colorScheme.primary);
      expect(shadow.color.a, greaterThan(0.25));
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
