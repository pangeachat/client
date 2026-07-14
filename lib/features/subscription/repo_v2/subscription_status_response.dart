import 'package:collection/collection.dart';

import 'package:fluffychat/features/subscription/enums/entitlement_source_enum.dart';
import 'package:fluffychat/features/subscription/enums/manage_account_kind_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_duration_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_provider_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_status_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_type_enum.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';

class SubscriptionStatusResponse extends BaseResponse {
  final SubscriptionAccessLevel accessLevel;
  final EntitlementSource entitlementSource;
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
    required this.manageEligible,
    required this.trialEligible,
    required this.trialClaimed,
    this.trialEndsAt,
  });

  factory SubscriptionStatusResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatusResponse(
      accessLevel: SubscriptionAccessLevel.fromString(
        json['access_level'] as String,
      ),
      entitlementSource: EntitlementSource.fromString(
        json['entitlement_source'] as String,
      ),
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
      'entitlement_source': entitlementSource.name,
      'winning': winning?.toJson(),
      'billing_issue': billingIssue?.toJson(),
      'entitlements': entitlements.map((e) => e.toJson()).toList(),
      'manage_eligible': manageEligible,
      'trial_eligible': trialEligible,
      'trial_claimed': trialClaimed,
      'trial_ends_at': trialEndsAt?.toIso8601String(),
    };
  }
}

class SubscriptionWinning {
  final SubscriptionType type;
  final SubscriptionStatus status;
  final DateTime? endsAt;
  final DateTime? paidThroughAt;
  final DateTime? graceEndsAt;
  final bool cancelAtPeriodEnd;
  final SubscriptionProvider provider;
  final String? planId;
  final String? entitlementRef;

  const SubscriptionWinning({
    required this.type,
    required this.status,
    this.endsAt,
    this.paidThroughAt,
    this.graceEndsAt,
    required this.cancelAtPeriodEnd,
    required this.provider,
    this.planId,
    this.entitlementRef,
  });

  factory SubscriptionWinning.fromJson(Map<String, dynamic> json) {
    return SubscriptionWinning(
      type: SubscriptionType.fromString(json['type'] as String),
      status: SubscriptionStatus.fromString(json['status'] as String),
      endsAt: _parseDate(json['ends_at']),
      paidThroughAt: _parseDate(json['paid_through_at']),
      graceEndsAt: _parseDate(json['grace_ends_at']),
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
      provider: SubscriptionProvider.fromString(json['provider'] as String),
      planId: json['planId'] as String?,
      entitlementRef: json['entitlementRef'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'status': status.name,
      'ends_at': endsAt?.toIso8601String(),
      'paid_through_at': paidThroughAt?.toIso8601String(),
      'grace_ends_at': graceEndsAt?.toIso8601String(),
      'cancel_at_period_end': cancelAtPeriodEnd,
      'provider': provider.name,
      'planId': planId,
      'entitlementRef': entitlementRef,
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value as String);
  }

  SubscriptionDuration get duration =>
      SubscriptionDuration.values.firstWhereOrNull((d) => d.name == planId) ??
      SubscriptionDuration.month;
}

class SubscriptionEntitlement {
  final String entitlementRef;
  final SubscriptionType type;
  final SubscriptionProvider provider;
  final String? planId;
  final String? sourceSubscriptionId;
  final bool cancelable;
  final SubscriptionStatus status;
  final ManageAction? manageAction;

  const SubscriptionEntitlement({
    required this.entitlementRef,
    required this.type,
    required this.provider,
    this.planId,
    this.sourceSubscriptionId,
    required this.cancelable,
    required this.status,
    this.manageAction,
  });

  factory SubscriptionEntitlement.fromJson(Map<String, dynamic> json) {
    return SubscriptionEntitlement(
      entitlementRef: json['entitlementRef'] as String,
      type: SubscriptionType.fromString(json['type'] as String),
      provider: SubscriptionProvider.fromString(json['provider'] as String),
      planId: json['planId'] as String?,
      sourceSubscriptionId: json['sourceSubscriptionId'] as String?,
      cancelable: json['cancelable'] as bool? ?? false,
      status: SubscriptionStatus.fromString(json['status'] as String),
      manageAction: json['manage_action'] != null
          ? ManageAction.fromJson(json['manage_action'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entitlementRef': entitlementRef,
      'type': type.name,
      'provider': provider.name,
      'planId': planId,
      'sourceSubscriptionId': sourceSubscriptionId,
      'cancelable': cancelable,
      'status': status.name,
      'manage_action': manageAction?.toJson(),
    };
  }
}

class BillingIssue {
  final bool present;
  final String? reason;
  final String? action;

  const BillingIssue({required this.present, this.reason, this.action});

  factory BillingIssue.fromJson(Map<String, dynamic> json) {
    return BillingIssue(
      present: json['present'] as bool? ?? false,
      reason: json['reason'] as String?,
      action: json['action'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'present': present, 'reason': reason, 'action': action};
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
