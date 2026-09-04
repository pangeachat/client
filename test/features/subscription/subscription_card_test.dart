import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/widgets/subscription_card.dart';

/// Covers #8751: the subscription surfaces used to wrap their content in an
/// opaque `colorScheme.surface` slab, which blanked out the star art behind it
/// everywhere except the thin margins. The slab is gone, so the stars show
/// through between the cards and only cards occlude them.
///
/// The other half of that rule is that no text ends up straight on the image,
/// which is what this card supplies. It has to be opaque in both themes: a
/// translucent or absent fill puts body text back over the art.
void main() {
  ThemeData themeFor(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: AppConfig.primaryColor,
    ),
  );

  for (final brightness in Brightness.values) {
    testWidgets('is an opaque surface in the ${brightness.name} theme', (
      tester,
    ) async {
      final theme = themeFor(brightness);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(child: SubscriptionCard(child: Text('trial ends'))),
          ),
        ),
      );

      final decoration =
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byType(SubscriptionCard),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration
              as BoxDecoration;

      expect(decoration.color, theme.colorScheme.surface);
      expect(
        decoration.color!.a,
        1.0,
        reason: 'a see-through card puts text back on the star art',
      );
    });
  }

  testWidgets('leaves its child visible and unwrapped in semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFor(Brightness.light),
        home: const Scaffold(
          body: Center(child: SubscriptionCard(child: Text('trial ends'))),
        ),
      ),
    );

    expect(find.text('trial ends'), findsOneWidget);
  });
}
