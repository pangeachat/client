import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/enums/manage_account_kind_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_type_enum.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';

/// Real-shaped `/subscription/status` fixtures matching choreo
/// `SubscriptionStatusResponseResponse` (status_v2_schema.py). JSON keys mirror the
/// Pydantic field names verbatim: snake_case for `access_level`,
/// `entitlement_source`, `ends_at`, `cancel_at_period_end`, `manage_action`,
/// `trial_*`; camelCase for `entitlementRef`, `sourceSubscriptionId`, `planId`.
void main() {
  Map<String, dynamic> fullActivePaid() => {
    "access_level": "full",
    "entitlement_source": "cms",
    "winning": {
      "type": "paid",
      "status": "active",
      "ends_at": "2026-08-13T00:00:00+00:00",
      "paid_through_at": "2026-08-13T00:00:00+00:00",
      "grace_ends_at": null,
      "cancel_at_period_end": false,
      "provider": "stripe",
      "planId": "month",
    },
    "billing_issue": null,
    "entitlements": [
      {
        "entitlementRef": "ent_123",
        "type": "paid",
        "provider": "stripe",
        "sourceSubscriptionId": "sub_abc",
        "cancelable": true,
        "status": "active",
        "ends_at": "2026-08-13T00:00:00+00:00",
        "manage_action": {"kind": "portal", "entitlementRef": "ent_123"},
        "planId": "month",
      },
    ],
    "manage_eligible": true,
    "trial_eligible": false,
    "trial_claimed": false,
    "trial_ends_at": null,
  };

  group('SubscriptionStatusResponse.fromJson', () {
    test('full active paid with planId', () {
      final status = SubscriptionStatusResponse.fromJson(fullActivePaid());
      expect(status.accessLevel, SubscriptionAccessLevel.full);
      expect(status.entitlementSource, "cms");
      expect(status.manageEligible, true);

      final winning = status.winning!;
      expect(winning.type, SubscriptionType.paid);
      expect(winning.status, "active");
      expect(winning.planId, "month");
      expect(winning.provider, "stripe");
      expect(winning.cancelAtPeriodEnd, false);
      expect(winning.endsAt, DateTime.utc(2026, 8, 13));

      expect(status.entitlements.length, 1);
      final ent = status.entitlements.single;
      expect(ent.entitlementRef, "ent_123");
      expect(ent.cancelable, true);
      expect(ent.sourceSubscriptionId, "sub_abc");
      expect(ent.manageAction!.kind, ManageActionKind.portal);
      expect(ent.manageAction!.entitlementRef, "ent_123");
      expect(ent.planId, "month");
    });

    test('none (no access, trial-eligible)', () {
      final status = SubscriptionStatusResponse.fromJson({
        "access_level": "none",
        "entitlement_source": "cms",
        "winning": null,
        "billing_issue": null,
        "entitlements": <dynamic>[],
        "manage_eligible": false,
        "trial_eligible": true,
        "trial_claimed": false,
        "trial_ends_at": null,
      });
      expect(status.accessLevel, SubscriptionAccessLevel.none);
      expect(status.winning, isNull);
      expect(status.entitlements, isEmpty);
      expect(status.trialEligible, true);
    });

    test('cancel_at_period_end set on the winning sub', () {
      final json = fullActivePaid();
      (json["winning"] as Map)["cancel_at_period_end"] = true;
      final status = SubscriptionStatusResponse.fromJson(json);
      expect(status.winning!.cancelAtPeriodEnd, true);
      expect(status.winning!.endsAt, DateTime.utc(2026, 8, 13));
    });

    test('billing issue (past_due) with update_payment action', () {
      final json = fullActivePaid();
      (json["winning"] as Map)["status"] = "past_due";
      json["billing_issue"] = {
        "present": true,
        "reason": "past_due",
        "action": {"kind": "update_payment", "entitlementRef": "ent_123"},
      };
      final status = SubscriptionStatusResponse.fromJson(json);
      expect(status.billingIssue!.present, true);
      expect(status.billingIssue!.reason, "past_due");
      expect(status.billingIssue!.action!.kind, "update_payment");
      expect(status.billingIssue!.action!.entitlementRef, "ent_123");
    });

    test('comp (promotional, not cancelable)', () {
      final status = SubscriptionStatusResponse.fromJson({
        "access_level": "full",
        "entitlement_source": "cms",
        "winning": {
          "type": "comp",
          "status": "active",
          "ends_at": "2026-12-31T00:00:00+00:00",
          "cancel_at_period_end": false,
          "provider": "manual",
        },
        "entitlements": [
          {
            "entitlementRef": "ent_comp",
            "type": "comp",
            "provider": "manual",
            "cancelable": false,
            "status": "active",
          },
        ],
        "manage_eligible": false,
        "trial_eligible": false,
        "trial_claimed": false,
      });
      expect(status.winning!.type, SubscriptionType.comp);
      expect(status.entitlements.single.cancelable, false);
      // A comp's sourceSubscriptionId is suppressed server-side.
      expect(status.entitlements.single.sourceSubscriptionId, isNull);
    });

    test('seat (group-managed, not cancelable)', () {
      final status = SubscriptionStatusResponse.fromJson({
        "access_level": "full",
        "entitlement_source": "cms",
        "winning": {
          "type": "seat",
          "status": "active",
          "ends_at": "2026-09-01T00:00:00+00:00",
          "cancel_at_period_end": false,
          "provider": "stripe",
        },
        "entitlements": [
          {
            "entitlementRef": "ent_seat",
            "type": "seat",
            "provider": "stripe",
            "cancelable": false,
            "status": "active",
          },
        ],
        "manage_eligible": false,
      });
      expect(status.winning!.type, SubscriptionType.seat);
      expect(status.entitlements.single.cancelable, false);
    });

    test('trial active', () {
      final status = SubscriptionStatusResponse.fromJson({
        "access_level": "full",
        "entitlement_source": "cms",
        "winning": {
          "type": "trial",
          "status": "active",
          "ends_at": "2026-07-20T00:00:00+00:00",
          "cancel_at_period_end": false,
          "provider": "manual",
          "planId": null,
        },
        "entitlements": <dynamic>[],
        "manage_eligible": false,
        "trial_eligible": false,
        "trial_claimed": true,
        "trial_ends_at": "2026-07-20T00:00:00+00:00",
      });
      expect(status.winning!.type, SubscriptionType.trial);
      expect(status.winning!.planId, isNull);
      expect(status.trialClaimed, true);
      expect(status.trialEndsAt, DateTime.utc(2026, 7, 20));
    });

    test('tolerates missing optional keys and bad dates', () {
      final status = SubscriptionStatusResponse.fromJson({
        "access_level": "full",
        "entitlement_source": "cms",
        "winning": {
          "type": "paid",
          "status": "active",
          "ends_at": "not-a-date",
        },
      });
      expect(status.winning!.endsAt, isNull);
      expect(status.winning!.cancelAtPeriodEnd, false);
      expect(status.entitlements, isEmpty);
      expect(status.manageEligible, false);
    });

    test('reads plan_id fallback when backend uses snake_case', () {
      final status = SubscriptionStatusResponse.fromJson({
        "access_level": "full",
        "entitlement_source": "cms",
        "winning": {"type": "paid", "status": "active", "plan_id": "year"},
      });
      expect(status.winning!.planId, "year");
    });

    test(
      'reads winning.entitlementRef (camelCase and snake_case fallback)',
      () {
        final camel = SubscriptionStatusResponse.fromJson({
          "access_level": "full",
          "entitlement_source": "cms",
          "winning": {
            "type": "paid",
            "status": "active",
            "entitlementRef": "ent_win",
          },
        });
        expect(camel.winning!.entitlementRef, "ent_win");

        final snake = SubscriptionStatusResponse.fromJson({
          "access_level": "full",
          "entitlement_source": "cms",
          "winning": {
            "type": "paid",
            "status": "active",
            "entitlement_ref": "ent_win",
          },
        });
        expect(snake.winning!.entitlementRef, "ent_win");
      },
    );
  });
}
