import 'package:flutter/foundation.dart';

/// How the subscription purchase surface is presented, gated by the device
/// storefront and its country. The legality of steering a user to web checkout
/// differs per store — see the subscriptions Platform policy design doc. This
/// is a legal constraint, not a UX preference.
enum PurchasePresentation {
  /// Plans, prices, the discount field, and web checkout are all shown.
  full,

  /// The web is named as the place to subscribe, with no tappable link and no
  /// in-app checkout (non-US Android — Play's linkless-information allowance).
  webInfo,

  /// No purchase surface at all; at most a neutral message that names no
  /// destination (non-US iOS — Apple 3.1.1 anti-steering).
  hidden,
}

/// Country codes for which purchase steering is allowed. Holds both the ISO
/// alpha-2 form (Android billing config) and the alpha-3 form (iOS StoreKit
/// storefront) so a raw store code matches without normalization. Extend as
/// EU/Japan adoption or store settlements move the boundary.
const Set<String> kSteeringAllowedCountries = {'US', 'USA'};

/// Resolve how the purchase surface should be presented.
///
/// [storefrontCountry] is the raw code from the store API (alpha-3 on iOS,
/// alpha-2 on Android), or null when it is not yet resolved or unavailable — in
/// which case the conservative tier for the platform applies, because this
/// gates a legal constraint and a wrong guess risks a store-policy violation.
PurchasePresentation resolvePurchasePresentation({
  required bool isWeb,
  required TargetPlatform platform,
  required String? storefrontCountry,
  Set<String> steeringAllowed = kSteeringAllowedCountries,
}) {
  // The web app is not a storefront; steering is always allowed there.
  if (isWeb) return PurchasePresentation.full;

  final steeringOk =
      storefrontCountry != null &&
      steeringAllowed.contains(storefrontCountry.toUpperCase());
  if (steeringOk) return PurchasePresentation.full;

  // Not an allowed storefront (or the country isn't known yet) — fall to the
  // conservative tier for the platform.
  switch (platform) {
    case TargetPlatform.iOS:
      return PurchasePresentation.hidden; // Apple 3.1.1: no calls to action.
    case TargetPlatform.android:
      return PurchasePresentation.webInfo; // Play: linkless info permitted.
    default:
      // Desktop and other non-store targets behave like the web.
      return PurchasePresentation.full;
  }
}
