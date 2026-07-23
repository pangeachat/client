import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/utils/storefront_gate.dart';

void main() {
  group('resolvePurchasePresentation', () {
    PurchasePresentation resolve(
      TargetPlatform platform,
      String? country, {
      bool isWeb = false,
    }) => resolvePurchasePresentation(
      isWeb: isWeb,
      platform: platform,
      storefrontCountry: country,
    );

    test('web is always full, regardless of platform or country', () {
      for (final p in TargetPlatform.values) {
        expect(resolve(p, null, isWeb: true), PurchasePresentation.full);
        expect(resolve(p, 'FRA', isWeb: true), PurchasePresentation.full);
      }
    });

    test('US storefront is full on both mobile platforms', () {
      // iOS reports ISO alpha-3, Android alpha-2 — both must resolve to full.
      expect(resolve(TargetPlatform.iOS, 'USA'), PurchasePresentation.full);
      expect(resolve(TargetPlatform.android, 'US'), PurchasePresentation.full);
    });

    test('country match is case-insensitive', () {
      expect(resolve(TargetPlatform.iOS, 'usa'), PurchasePresentation.full);
      expect(resolve(TargetPlatform.android, 'us'), PurchasePresentation.full);
    });

    test('non-US iOS is hidden (Apple 3.1.1 anti-steering)', () {
      expect(resolve(TargetPlatform.iOS, 'FRA'), PurchasePresentation.hidden);
      expect(resolve(TargetPlatform.iOS, 'JPN'), PurchasePresentation.hidden);
    });

    test('non-US Android is webInfo (Play linkless information)', () {
      expect(
        resolve(TargetPlatform.android, 'FR'),
        PurchasePresentation.webInfo,
      );
      expect(
        resolve(TargetPlatform.android, 'JP'),
        PurchasePresentation.webInfo,
      );
    });

    test('unknown country falls to the conservative tier per platform', () {
      // Pre-resolution and read-failure both surface as a null country.
      expect(resolve(TargetPlatform.iOS, null), PurchasePresentation.hidden);
      expect(
        resolve(TargetPlatform.android, null),
        PurchasePresentation.webInfo,
      );
    });

    test('non-store desktop targets behave like the web', () {
      expect(resolve(TargetPlatform.macOS, null), PurchasePresentation.full);
      expect(resolve(TargetPlatform.windows, 'FRA'), PurchasePresentation.full);
    });

    test('a custom allowed set widens the full tier (EU/JP rollout)', () {
      expect(
        resolvePurchasePresentation(
          isWeb: false,
          platform: TargetPlatform.iOS,
          storefrontCountry: 'JPN',
          steeringAllowed: {'US', 'USA', 'JP', 'JPN'},
        ),
        PurchasePresentation.full,
      );
    });
  });
}
