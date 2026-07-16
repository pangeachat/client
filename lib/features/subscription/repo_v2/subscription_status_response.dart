import 'package:collection/collection.dart';

import 'package:fluffychat/features/subscription/enums/manage_account_kind_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_duration_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/date_formatter.dart';

class SubscriptionStatusResponse extends BaseResponse {
  final SubscriptionAccessLevel accessLevel;
  final String entitlementSource;
  final SubscriptionWinning? winning;
  final BillingIssue? billingIssue;
  final List<SubscriptionEntitlement> entitlements;
  final bool manageEligible;
  final bool trialEligible;
  final bool trialClaimed;
  final DateTime? trialEndsAt;

  const SubscriptionStatusResponse({
    required this.accessLevel,
    required this.entitlementSource,
    this.winning,
    this.billingIssue,
    required this.entitlements,
    this.manageEligible = false,
    this.trialEligible = false,
    this.trialClaimed = false,
    this.trialEndsAt,
  });

  factory SubscriptionStatusResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatusResponse(
      accessLevel: SubscriptionAccessLevel.fromString(
        json['access_level'] as String,
      ),
      entitlementSource: json['entitlement_source'] as String,
      winning: json['winning'] != null
          ? SubscriptionWinning.fromJson(
              json['winning'] as Map<String, dynamic>,
            )
          : null,
      billingIssue: json['billing_issue'] != null
          ? BillingIssue.fromJson(json['billing_issue'] as Map<String, dynamic>)
          : null,
      entitlements: (json['entitlements'] as List<dynamic>? ?? [])
          .map(
            (e) => SubscriptionEntitlement.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      manageEligible: json['manage_eligible'] as bool? ?? false,
      trialEligible: json['trial_eligible'] as bool? ?? false,
      trialClaimed: json['trial_claimed'] as bool? ?? false,
      trialEndsAt: json['trial_ends_at'] != null
          ? DateTime.parse(json['trial_ends_at'] as String)
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'access_level': accessLevel.name,
      'entitlement_source': entitlementSource,
      'winning': winning?.toJson(),
      'billing_issue': billingIssue?.toJson(),
      'entitlements': entitlements.map((e) => e.toJson()).toList(),
      'manage_eligible': manageEligible,
      'trial_eligible': trialEligible,
      'trial_claimed': trialClaimed,
      'trial_ends_at': trialEndsAt?.toIso8601String(),
    };
  }

  SubscriptionEntitlement? get winningEntitlement {
    final planId = winning?.planId;
    if (planId == null) return null;
    return entitlements.firstWhereOrNull((e) => e.planId == planId);
  }

  bool get isTrialOfferable => trialEligible == true && trialClaimed != true;

  bool get isPaidWithoutPlan {
    final winning = this.winning;
    return accessLevel == SubscriptionAccessLevel.full &&
        winning != null &&
        winning.planId == null &&
        winning.type?.isBillable == true;
  }
}

class SubscriptionWinning {
  final SubscriptionType? type;
  final String status;
  final DateTime? endsAt;
  final DateTime? paidThroughAt;
  final DateTime? graceEndsAt;
  final bool cancelAtPeriodEnd;
  final String? provider;
  final String? planId;
  final String? entitlementRef;

  const SubscriptionWinning({
    this.type,
    required this.status,
    this.endsAt,
    this.paidThroughAt,
    this.graceEndsAt,
    this.cancelAtPeriodEnd = false,
    this.provider,
    this.planId,
    this.entitlementRef,
  });

  factory SubscriptionWinning.fromJson(Map<String, dynamic> json) {
    return SubscriptionWinning(
      type: SubscriptionType.fromString(json['type'] as String),
      status: json['status'] as String,
      endsAt: _parseDate(json['ends_at']),
      paidThroughAt: _parseDate(json['paid_through_at']),
      graceEndsAt: _parseDate(json['grace_ends_at']),
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
      provider: json['provider'] as String?,
      planId: json['planId'] as String? ?? json['plan_id'] as String?,
      entitlementRef:
          json['entitlementRef'] as String? ??
          json['entitlement_ref'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type?.name,
      'status': status,
      'ends_at': endsAt?.toIso8601String(),
      'paid_through_at': paidThroughAt?.toIso8601String(),
      'grace_ends_at': graceEndsAt?.toIso8601String(),
      'cancel_at_period_end': cancelAtPeriodEnd,
      'provider': provider,
      'planId': planId,
      'entitlementRef': entitlementRef,
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value as String);
  }

  SubscriptionDuration? get _duration =>
      SubscriptionDuration.values.firstWhereOrNull((d) => d.name == planId);

  String subscriptionTitle(L10n l10n) {
    final fallback = l10n.currentSubscription;
    return switch (type) {
      SubscriptionType.paid ||
      SubscriptionType.individual => _duration?.copy(l10n) ?? fallback,
      SubscriptionType.trial => l10n.freeTrial,
      SubscriptionType.comp => l10n.promoSubscription,
      SubscriptionType.seat => l10n.seatSubscription,
      null => fallback,
    };
  }

  String? paymentPeriodDescription(L10n l10n) {
    final endsAt = this.endsAt;
    switch (type) {
      case SubscriptionType.paid:
      case SubscriptionType.individual:
      case SubscriptionType.seat:
        if (endsAt == null) return null;
        return cancelAtPeriodEnd
            ? l10n.subscriptionEndsOn(DateFormatter.format(endsAt))
            : l10n.subscriptionRenewsOn(DateFormatter.format(endsAt));
      case SubscriptionType.comp:
        if (endsAt == null || endsAt.isAfter(DateTime(2100))) {
          return l10n.lifetimeSubscription;
        }
        return l10n.subscriptionEndsOn(DateFormatter.format(endsAt));
      case SubscriptionType.trial:
        if (endsAt == null) return l10n.freeTrialDescription;
        return l10n.trialExpiration(DateFormatter.format(endsAt));
      case null:
        if (endsAt == null) return null;
        return l10n.subscriptionEndsOn(DateFormatter.format(endsAt));
    }
  }

  String? priceDisplay(L10n l10n) {
    return switch (type) {
      SubscriptionType.paid || SubscriptionType.individual || null => null,
      SubscriptionType.trial ||
      SubscriptionType.comp ||
      SubscriptionType.seat => l10n.freeSubscription,
    };
  }
}

class SubscriptionEntitlement {
  final String entitlementRef;
  final SubscriptionType? type;
  final String? provider;
  final String? sourceSubscriptionId;
  final bool cancelable;
  final String status;
  final DateTime? endsAt;
  final ManageAction? manageAction;
  final String? planId;

  const SubscriptionEntitlement({
    required this.entitlementRef,
    this.type,
    this.provider,
    this.sourceSubscriptionId,
    required this.cancelable,
    required this.status,
    this.endsAt,
    this.manageAction,
    this.planId,
  });

  factory SubscriptionEntitlement.fromJson(Map<String, dynamic> json) {
    return SubscriptionEntitlement(
      entitlementRef: json['entitlementRef'] as String,
      type: SubscriptionType.fromString(json['type'] as String),
      provider: json['provider'] as String?,
      planId: json['planId'] as String? ?? json['plan_id'] as String?,
      sourceSubscriptionId: json['sourceSubscriptionId'] as String?,
      cancelable: json['cancelable'] as bool? ?? false,
      status: json['status'] as String,
      manageAction: json['manage_action'] != null
          ? ManageAction.fromJson(json['manage_action'] as Map<String, dynamic>)
          : null,
      endsAt: json['ends_at'] != null
          ? DateTime.tryParse(json['ends_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entitlementRef': entitlementRef,
      'type': type?.name,
      'provider': provider,
      'planId': planId,
      'sourceSubscriptionId': sourceSubscriptionId,
      'cancelable': cancelable,
      'status': status,
      'manage_action': manageAction?.toJson(),
      'ends_at': endsAt?.toIso8601String(),
    };
  }
}

class BillingIssue {
  final bool present;
  final String? reason;
  final ActionDescriptor? action;

  const BillingIssue({required this.present, this.reason, this.action});

  factory BillingIssue.fromJson(Map<String, dynamic> json) {
    return BillingIssue(
      present: json['present'] as bool? ?? false,
      reason: json['reason'] as String?,
      action: json['action'] == null
          ? null
          : ActionDescriptor.fromJson(
              Map<String, dynamic>.from(json['action'] as Map),
            ),
    );
  }

  Map<String, dynamic> toJson() {
    return {'present': present, 'reason': reason, 'action': action?.toJson()};
  }
}

class ActionDescriptor {
  /// "portal" | "update_payment".
  final String kind;
  final String entitlementRef;

  const ActionDescriptor({required this.kind, required this.entitlementRef});

  factory ActionDescriptor.fromJson(Map<String, dynamic> json) =>
      ActionDescriptor(
        kind: json['kind'] as String? ?? "",
        entitlementRef: json['entitlementRef'] as String? ?? "",
      );

  Map<String, dynamic> toJson() {
    return {'kind': kind, 'entitlementRef': entitlementRef};
  }
}

class ManageAction {
  final ManageActionKind kind;
  final String entitlementRef;

  const ManageAction({required this.kind, required this.entitlementRef});

  factory ManageAction.fromJson(Map<String, dynamic> json) {
    return ManageAction(
      kind: ManageActionKind.fromString(json['kind'] as String),
      entitlementRef: json['entitlementRef'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'kind': kind.name, 'entitlementRef': entitlementRef};
  }
}
