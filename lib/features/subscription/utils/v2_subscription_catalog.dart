import 'package:collection/collection.dart';

import 'package:fluffychat/features/subscription/models/products_v2_response.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_status_v2.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';

/// The two catalog lists the controller exposes on the v2 web path, derived
/// PURELY (no I/O, no clock, no singleton) from the `/products` plans and the
/// `/status` snapshot — so the trial-card + trial-resolution logic is
/// unit-testable in isolation of `MatrixState`.
class V2SubscriptionCatalog {
  /// Every subscription the controller can resolve `subscription` against —
  /// the sellable plans plus (when relevant) the trial, so an ACTIVE trial's
  /// `subscriptionId == kV2TrialId` resolves to its tile.
  final List<SubscriptionDetails> all;

  /// The plans (plus a synthesized trial card when the user can start one) to
  /// render on the paywall, sorted by price.
  final List<SubscriptionDetails> available;

  const V2SubscriptionCatalog({required this.all, required this.available});
}

/// The synthesized trial card / active-trial tile (D3/D7): a $0, appId=="trial"
/// [SubscriptionDetails] with the [kV2TrialId] id, so `isTrial` is true and the
/// controller `subscription` getter resolves an active trial by id.
SubscriptionDetails v2TrialSubscription() => SubscriptionDetails(
  id: kV2TrialId,
  appId: "trial",
  price: 0,
);

/// Builds the v2 web catalog from the storefront [plans] and the [status]
/// snapshot (D3, finding #11).
///
/// - Plans map through [productV2ToSubscriptionDetails] (`appId = stripeAppId`,
///   `id = planId`); an unknown plan id THROWS [UnknownPlanIdException] (I4) —
///   propagated to fail closed rather than silently degrade.
/// - `available` = plans + a synthesized trial card iff the user can START a
///   trial (`trialEligible && !trialClaimed`), sorted by price.
/// - `all` = plans + a trial [SubscriptionDetails] whenever a trial is
///   startable (`trialEligible`) OR one is currently ACTIVE, so the
///   current-subscription getter resolves for an active trial.
V2SubscriptionCatalog buildV2SubscriptionCatalog(
  List<ProductV2> plans,
  SubscriptionStatusV2? status, {
  required String stripeAppId,
}) {
  final mapped = plans
      .map((p) => productV2ToSubscriptionDetails(p, stripeAppId: stripeAppId))
      .sorted((a, b) => a.price.compareTo(b.price))
      .toList();

  final bool trialEligible = status?.trialEligible ?? false;
  final bool trialClaimed = status?.trialClaimed ?? false;
  final bool trialActive =
      status != null &&
      status.accessLevel == "full" &&
      status.winning?.type == "trial";

  // Reuse ONE synthesized trial object across both lists (finding #3), so an
  // active trial is identified by the same stable instance/id in `all` and
  // `available` — never two divergent objects.
  final SubscriptionDetails? trial = (trialEligible || trialActive)
      ? v2TrialSubscription()
      : null;

  final all = List<SubscriptionDetails>.from(mapped);
  if (trial != null) {
    all.add(trial);
  }

  final available = List<SubscriptionDetails>.from(mapped);
  if (trial != null && trialEligible && !trialClaimed) {
    available.add(trial);
  }

  return V2SubscriptionCatalog(
    all: all,
    available: available.sorted((a, b) => a.price.compareTo(b.price)).toList(),
  );
}
