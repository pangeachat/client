import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';

/// The v2 winning `type` values that represent a BILLABLE, user-paid
/// subscription — as opposed to a granted one (`seat`/`comp`) or a `trial`.
/// `individual` is the RC-era paid type; treating only `"paid"` as billable
/// would misclassify an individual-plan payer as promotional, skipping their
/// account-delete warning and paid tile. Centralized so every paid/promotional
/// decision agrees. Lives here (with the mapper) rather than in `v2_ui_gating`
/// to avoid a circular import.
const Set<String> kV2PaidTypes = {"paid", "individual"};

/// Whether a v2 winning `type` is a billable, user-paid subscription (see
/// [kV2PaidTypes]).
bool isV2PaidType(String? type) => type != null && kV2PaidTypes.contains(type);

/// Client model for the Subscriptions-v2 `/subscription/status` response
/// (choreo `SubscriptionStatusV2Response`, status_v2_schema.py). The client
/// ALWAYS consumes this shape — never raw RC JSON — in both the RC (pre-flip)
/// and CMS (post-flip) phases; the source is transparent behind
/// [entitlementSource]. JSON keys mirror the Pydantic field names verbatim
/// (a mix of snake_case and camelCase), so they are read exactly as the server
/// emits them. All dates parse via `DateTime.tryParse` and tolerate nulls.
class SubscriptionStatusV2 {
  /// "full" | "none".
  final String accessLevel;

  /// "rc" | "cms".
  final String entitlementSource;

  final WinningSummaryV2? winning;
  final BillingIssueV2? billingIssue;
  final List<EntitlementV2> entitlements;
  final bool manageEligible;
  final bool trialEligible;
  final bool trialClaimed;
  final DateTime? trialEndsAt;

  const SubscriptionStatusV2({
    required this.accessLevel,
    required this.entitlementSource,
    this.winning,
    this.billingIssue,
    this.entitlements = const [],
    this.manageEligible = false,
    this.trialEligible = false,
    this.trialClaimed = false,
    this.trialEndsAt,
  });

  factory SubscriptionStatusV2.fromJson(Map<String, dynamic> json) {
    final rawEntitlements =
        (json['entitlements'] as List<dynamic>?) ?? const <dynamic>[];
    return SubscriptionStatusV2(
      accessLevel: json['access_level'] as String? ?? "none",
      entitlementSource: json['entitlement_source'] as String? ?? "cms",
      winning: json['winning'] == null
          ? null
          : WinningSummaryV2.fromJson(
              Map<String, dynamic>.from(json['winning'] as Map),
            ),
      billingIssue: json['billing_issue'] == null
          ? null
          : BillingIssueV2.fromJson(
              Map<String, dynamic>.from(json['billing_issue'] as Map),
            ),
      entitlements: rawEntitlements
          .map(
            (e) => EntitlementV2.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      manageEligible: json['manage_eligible'] as bool? ?? false,
      trialEligible: json['trial_eligible'] as bool? ?? false,
      trialClaimed: json['trial_claimed'] as bool? ?? false,
      trialEndsAt: _tryParseDate(json['trial_ends_at']),
    );
  }
}

/// The single entitlement that defines the user's access (display precedence).
class WinningSummaryV2 {
  /// paid | seat | comp | trial | individual (RC always emits "paid").
  final String type;
  final String status;
  final DateTime? endsAt;
  final DateTime? paidThroughAt;
  final DateTime? graceEndsAt;
  final bool cancelAtPeriodEnd;
  final String? provider;

  /// The catalog plan id ("month" | "year"), added to the backend by S-BE
  /// (reverse-mapped from the entitlement's stored priceId). Null on the RC
  /// path and for entitlements with no known plan.
  final String? planId;

  /// The owner-scoped Stripe subscription id, when the backend exposes it on
  /// the winning summary. Kept nullable so the cancel entitlement selection can
  /// disambiguate a matching row when [entitlementRef] is absent (I10).
  final String? sourceSubscriptionId;

  /// The ref of the entitlement that IS the winning one, added to the backend
  /// by S-BE. When present it identifies THE cancel target unambiguously —
  /// preferred over scanning the entitlements list (I10). Null on older
  /// backends / the RC path.
  final String? entitlementRef;

  const WinningSummaryV2({
    required this.type,
    required this.status,
    this.endsAt,
    this.paidThroughAt,
    this.graceEndsAt,
    this.cancelAtPeriodEnd = false,
    this.provider,
    this.planId,
    this.sourceSubscriptionId,
    this.entitlementRef,
  });

  factory WinningSummaryV2.fromJson(Map<String, dynamic> json) =>
      WinningSummaryV2(
        type: json['type'] as String? ?? "",
        status: json['status'] as String? ?? "",
        endsAt: _tryParseDate(json['ends_at']),
        paidThroughAt: _tryParseDate(json['paid_through_at']),
        graceEndsAt: _tryParseDate(json['grace_ends_at']),
        cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
        provider: json['provider'] as String?,
        planId: json['planId'] as String? ?? json['plan_id'] as String?,
        sourceSubscriptionId: json['sourceSubscriptionId'] as String?,
        entitlementRef:
            json['entitlementRef'] as String? ??
            json['entitlement_ref'] as String?,
      );
}

class BillingIssueV2 {
  final bool present;
  final String? reason;
  final ActionDescriptorV2? action;

  const BillingIssueV2({required this.present, this.reason, this.action});

  factory BillingIssueV2.fromJson(Map<String, dynamic> json) => BillingIssueV2(
    present: json['present'] as bool? ?? false,
    reason: json['reason'] as String?,
    action: json['action'] == null
        ? null
        : ActionDescriptorV2.fromJson(
            Map<String, dynamic>.from(json['action'] as Map),
          ),
  );
}

/// A first-party action descriptor — resolved to a live provider URL only by
/// the dedicated portal endpoint, NEVER a live URL here.
class ActionDescriptorV2 {
  /// "portal" | "update_payment".
  final String kind;
  final String entitlementRef;

  const ActionDescriptorV2({required this.kind, required this.entitlementRef});

  factory ActionDescriptorV2.fromJson(Map<String, dynamic> json) =>
      ActionDescriptorV2(
        kind: json['kind'] as String? ?? "",
        entitlementRef: json['entitlementRef'] as String? ?? "",
      );
}

class EntitlementV2 {
  final String entitlementRef;
  final String type;
  final String? provider;
  final String? sourceSubscriptionId;
  final bool cancelable;

  /// Whether THIS entitlement is already set to cancel at period end. The
  /// backend does not currently emit a per-entitlement flag (only the winning
  /// summary carries `cancel_at_period_end`), so this defaults to false and the
  /// effective guard is the winning value carried on the state. Kept for I10's
  /// selection predicate and forward-compatibility if the backend adds it.
  final bool cancelAtPeriodEnd;

  final String status;
  final DateTime? endsAt;
  final ActionDescriptorV2? manageAction;
  final String? planId;

  const EntitlementV2({
    required this.entitlementRef,
    required this.type,
    this.provider,
    this.sourceSubscriptionId,
    this.cancelable = false,
    this.cancelAtPeriodEnd = false,
    required this.status,
    this.endsAt,
    this.manageAction,
    this.planId,
  });

  factory EntitlementV2.fromJson(Map<String, dynamic> json) => EntitlementV2(
    entitlementRef: json['entitlementRef'] as String? ?? "",
    type: json['type'] as String? ?? "",
    provider: json['provider'] as String?,
    sourceSubscriptionId: json['sourceSubscriptionId'] as String?,
    cancelable: json['cancelable'] as bool? ?? false,
    cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
    status: json['status'] as String? ?? "",
    endsAt: _tryParseDate(json['ends_at']),
    manageAction: json['manage_action'] == null
        ? null
        : ActionDescriptorV2.fromJson(
            Map<String, dynamic>.from(json['manage_action'] as Map),
          ),
    planId: json['planId'] as String? ?? json['plan_id'] as String?,
  );
}

DateTime? _tryParseDate(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// The selected cancel entitlement for a winning subscription — its ref and
/// whether an in-app cancel is offered (I10). Internal to the mapper.
class _CancelSelection {
  final String? entitlementRef;
  final bool cancelable;
  const _CancelSelection(this.entitlementRef, this.cancelable);

  static const _CancelSelection none = _CancelSelection(null, false);
}

/// PURE adapter: a v2 `/status` payload -> the existing [SubscriptionState]
/// shape (D7/I7/I10/I11). Deterministic, no I/O, no clock.
///
/// - `access_level == "none"` OR no winning -> [SubscriptionInactive].
/// - `access_level == "full"` with a winning -> [SubscriptionActive] where:
///   - `subscriptionId`: for an ACTIVE TRIAL (`winning.type == "trial"`) this is
///     the [kV2TrialId] sentinel so the controller `subscription` getter
///     resolves the synthesized trial tile (which the wiring layer keys off to
///     render trial copy). Otherwise `winning.planId ?? stripeAppId` (stable
///     non-null id; the stripeAppId fallback resolves no product tile, which is
///     correct for a comp/seat that has no catalog plan).
///   - `expirationDate = winning.endsAt`.
///   - `unsubscribeDetectedAt = winning.cancelAtPeriodEnd ? winning.endsAt : null`
///     (so the RC-coupled `subscriptionEndDate` getter keeps working, D7/#6).
///   - `cancelAtPeriodEnd = winning.cancelAtPeriodEnd`.
///   - `isPromotional = !isV2PaidType(winning.type)` (I11) — paid/individual
///     are billable; seat/comp/trial are promotional.
///   - `isTrial = winning.type == "trial"` (D7 trial clause).
///   - the cancel `entitlementRef`/`cancelable` from [_selectCancelEntitlement]
///     (I10) — never a Stripe id.
SubscriptionState mapStatusV2ToState(
  SubscriptionStatusV2 status, {
  required String stripeAppId,
}) {
  final winning = status.winning;
  if (status.accessLevel != "full" || winning == null) {
    return SubscriptionInactive();
  }

  final cancel = _selectCancelEntitlement(status.entitlements, winning);
  final bool isTrial = winning.type == "trial";

  return SubscriptionActive(
    subscriptionId: isTrial ? kV2TrialId : (winning.planId ?? stripeAppId),
    expirationDate: winning.endsAt,
    unsubscribeDetectedAt: winning.cancelAtPeriodEnd ? winning.endsAt : null,
    cancelAtPeriodEnd: winning.cancelAtPeriodEnd,
    isPromotional: !isV2PaidType(winning.type),
    isTrial: isTrial,
    entitlementRef: cancel.entitlementRef,
    cancelable: cancel.cancelable,
  );
}

/// Deterministic, safe cancel-entitlement selection (I10). Correctness beats
/// offering a cancel button: it must NEVER target the wrong subscription.
///
/// 1. When the backend names the winning entitlement (`winning.entitlementRef`),
///    that ref IS the cancel target — subject to its row being user-cancelable
///    and the winning not already set to cancel at period end. If the named row
///    is absent or not cancelable, offer NO cancel.
/// 2. Otherwise (older backend / RC path) scan the entitlements for rows that
///    are `cancelable && !cancelAtPeriodEnd && entitlementRef != ""`:
///    - exactly one -> that row;
///    - more than one -> disambiguate ONLY by a `sourceSubscriptionId` that
///      matches the winning's and is unique; if there is no such discriminator,
///      offer NO cancel rather than guess (defensive: never cancel the wrong
///      sub);
///    - none -> no cancel.
_CancelSelection _selectCancelEntitlement(
  List<EntitlementV2> entitlements,
  WinningSummaryV2 winning,
) {
  // The winning subscription is already ending; there is nothing to cancel.
  if (winning.cancelAtPeriodEnd) return _CancelSelection.none;

  bool isCancelable(EntitlementV2 e) =>
      e.cancelable && !e.cancelAtPeriodEnd && e.entitlementRef.isNotEmpty;

  // 1. Preferred: the backend tells us exactly which entitlement is winning.
  final winningRef = winning.entitlementRef;
  if (winningRef != null && winningRef.isNotEmpty) {
    final row = _firstOrNull(
      entitlements.where((e) => e.entitlementRef == winningRef),
    );
    if (row != null && isCancelable(row)) {
      return _CancelSelection(row.entitlementRef, true);
    }
    // Named winner is absent or not user-cancelable -> no cancel affordance.
    return _CancelSelection.none;
  }

  // 2. Fallback scan for backends that do not name the winner.
  final candidates = entitlements.where(isCancelable).toList();
  if (candidates.isEmpty) return _CancelSelection.none;
  if (candidates.length == 1) {
    return _CancelSelection(candidates.single.entitlementRef, true);
  }

  // Ambiguous: more than one cancelable row. The only trustworthy discriminator
  // is a unique sourceSubscriptionId match to the winning's; anything else would
  // be a guess.
  final winningSourceId = winning.sourceSubscriptionId;
  if (winningSourceId != null && winningSourceId.isNotEmpty) {
    final matched = candidates
        .where((e) => e.sourceSubscriptionId == winningSourceId)
        .toList();
    if (matched.length == 1) {
      return _CancelSelection(matched.single.entitlementRef, true);
    }
  }
  return _CancelSelection.none;
}

EntitlementV2? _firstOrNull(Iterable<EntitlementV2> items) {
  final it = items.iterator;
  return it.moveNext() ? it.current : null;
}
