import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/models/subscription_status_v2.dart';
import 'package:fluffychat/features/subscription/utils/cancel_eligibility.dart';

/// PURE decision helpers for the v2 web UI (no I/O, no clock, no singleton), so
/// the flag-gated wiring in the widgets/controller stays testable in isolation.
/// Each is a plain function of already-resolved inputs; the `subsV2WebEnabled &&
/// kIsWeb` gate lives at the CALL sites so the flag-off + mobile paths never
/// reach these decisions.

/// Whether a v2 trial can be STARTED given the [status] snapshot (D3):
/// server-eligible and not already claimed. This DRIVES trial-card enablement
/// on the v2 web path (paywall / change-subscription), replacing the RC-only
/// `inTrialWindow()` heuristic — a server-eligible trial must render enabled
/// even when the local trial window has lapsed (finding: v2 trial not
/// activatable).
bool v2TrialOfferableFor(SubscriptionStatusV2? status) =>
    status?.trialEligible == true && status?.trialClaimed != true;

/// A billable v2 entitlement (paid/individual — see [isV2PaidType]) whose plan
/// is missing from the catalog (null `planId`) — an anomaly the catalog should
/// prevent (current subs should always map to a sellable plan). Used to LOG the
/// anomaly and to justify the generic-tile fallback so a paying, grandfathered
/// user never sees a broken tile or silently loses the account-delete warning
/// (finding: paid Stripe access without planId).
bool isPaidWithoutPlan(SubscriptionStatusV2 status) {
  final winning = status.winning;
  return status.accessLevel == "full" &&
      winning != null &&
      isV2PaidType(winning.type) &&
      winning.planId == null;
}

/// Path-aware "can a trial be offered / auto-activated". On the v2 web path the
/// SERVER signal ([v2TrialOfferable], = `trialEligible && !trialClaimed`) decides
/// — a server-eligible trial must be offered even when the local trial window
/// has lapsed. Off the flag / on mobile it stays on the RC [inTrialWindow]
/// heuristic, so those paths are byte-for-byte unchanged. Drives BOTH the
/// controller auto-activation and the paywall top-level trial branch.
bool isTrialOfferable({
  required bool v2Path,
  required bool v2TrialOfferable,
  required bool inTrialWindow,
}) => v2Path ? v2TrialOfferable : inTrialWindow;

/// What a cancel-tile tap should do. The v2 path is SELF-CONTAINED: it either
/// runs the in-app cancel or no-ops — it MUST NEVER fall through to the legacy
/// external-portal + clicked-cancel polling shim (finding: v2 cancel handler
/// not self-gated). Only the non-v2 path is [legacy].
enum CancelClickAction { v2Cancel, v2NoOp, legacy }

CancelClickAction classifyCancelClick({
  required bool v2CancelPath,
  required SubscriptionState state,
}) {
  if (v2CancelPath) {
    return (state is SubscriptionActive && shouldShowV2Cancel(state))
        ? CancelClickAction.v2Cancel
        : CancelClickAction.v2NoOp;
  }
  return CancelClickAction.legacy;
}

/// Where the management actions (payment method / payment history) route.
/// DECISION (subs-v2 wiring): on the v2 web path BOTH tiles mint a fresh
/// Stripe billing-portal session — the portal surfaces the payment method AND
/// the full invoice history, which is the minimal correct wiring onto the
/// canonical v2 APIs without building new client UI (Gabby's history page will
/// consume `PaymentHistoryRepo` directly). The legacy static
/// `stripeManagementUrl` is NEVER launched on the v2 path. Off the flag / on
/// mobile the legacy behavior is byte-for-byte unchanged.
enum ManagementLaunchRoute { v2BillingPortal, legacy }

ManagementLaunchRoute classifyManagementLaunch({required bool v2Path}) => v2Path
    ? ManagementLaunchRoute.v2BillingPortal
    : ManagementLaunchRoute.legacy;

/// Whether the promotional-access warning should use the UNDATED copy (no
/// expiration date). True for a lifetime/comp/seat/manual grant whose expiration
/// is null — force-unwrapping the date there would crash (finding: settings NPE
/// for comp/seat). When false, the caller has a non-null expiration to format.
bool showUndatedPromoWarning({
  required bool isLifetime,
  required DateTime? expiration,
}) => isLifetime || expiration == null;

/// Whether to warn a user before deleting their account. On the v2 path we warn
/// for ANY active paid access — even when no management URL resolves (a paid
/// entitlement whose plan is not in the catalog still bills the user), so a
/// paying user can never delete their account with no warning (finding: paid
/// Stripe access without planId — safety). Off the v2 path the behavior is
/// exactly today's: warn only when a paid sub AND a management URL resolve.
bool shouldWarnBeforeAccountDelete({
  required bool hasPaidSubscription,
  required bool hasManagementUrl,
  required bool v2Path,
}) => hasPaidSubscription && (hasManagementUrl || v2Path);
