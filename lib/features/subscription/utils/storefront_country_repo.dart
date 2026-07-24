import 'package:flutter/foundation.dart';

import 'package:in_app_purchase/in_app_purchase.dart';

/// Reads the device store's storefront country.
///
/// This is the ONLY place that touches the `in_app_purchase` plugin — isolated
/// so it can be swapped for a minimal platform channel when that dependency is
/// finally removed with the rest of the in-app-purchase teardown.
///
/// Returns the raw store country code (ISO alpha-3 on iOS from StoreKit,
/// alpha-2 on Android from the billing config), or null when it can't be
/// determined (web, no signed-in store account, or any plugin error). A null is
/// treated as the conservative tier by [resolvePurchasePresentation].
class StorefrontCountryRepo {
  static Future<String?> resolve() async {
    // `in_app_purchase` has no web implementation; the web app is not a
    // storefront and is handled by the presentation resolver directly.
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final code = await InAppPurchase.instance.countryCode();
      return code.isEmpty ? null : code;
    } catch (_) {
      // A storefront read failure is non-fatal (e.g. no store account): the
      // caller falls back to the conservative tier.
      return null;
    }
  }
}
