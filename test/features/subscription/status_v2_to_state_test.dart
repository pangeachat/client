import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/models/subscription_status_v2.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';

void main() {
  const stripeAppId = "stripe_app_1";
  final endsAt = DateTime.utc(2026, 8, 13);

  SubscriptionStatusV2 status({
    String accessLevel = "full",
    WinningSummaryV2? winning,
    List<EntitlementV2> entitlements = const [],
  }) => SubscriptionStatusV2(
    accessLevel: accessLevel,
    entitlementSource: "cms",
    winning: winning,
    entitlements: entitlements,
  );

  group('mapStatusV2ToState — inactive branch (I7)', () {
    test('access_level none -> Inactive', () {
      final state = mapStatusV2ToState(
        status(accessLevel: "none"),
        stripeAppId: stripeAppId,
      );
      expect(state, isA<SubscriptionInactive>());
    });

    test('full but no winning -> Inactive (fail-safe)', () {
      final state = mapStatusV2ToState(
        status(accessLevel: "full", winning: null),
        stripeAppId: stripeAppId,
      );
      expect(state, isA<SubscriptionInactive>());
    });
  });

  group('mapStatusV2ToState — paid active', () {
    test('maps id=planId, expiration, not promotional, not trial', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: WinningSummaryV2(
                    type: "paid",
                    status: "active",
                    endsAt: endsAt,
                    planId: "month",
                  ),
                  entitlements: [
                    EntitlementV2(
                      entitlementRef: "ent_123",
                      type: "paid",
                      cancelable: true,
                      status: "active",
                      sourceSubscriptionId: "sub_abc",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;

      expect(state.subscriptionId, "month");
      expect(state.expirationDate, endsAt);
      expect(state.unsubscribeDetectedAt, isNull);
      expect(state.cancelAtPeriodEnd, false);
      expect(state.isPromotional, false);
      expect(state.isTrial, false);
      expect(state.cancelable, true);
      expect(state.entitlementRef, "ent_123");
    });

    test('falls back to stripeAppId when winning has no planId', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "paid",
                    status: "active",
                  ),
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.subscriptionId, stripeAppId);
      // #4b: a PAID entitlement with no catalog planId stays classified as paid
      // (not promotional, not trial), so the controller renders a generic paid
      // tile with working management rather than a comp/seat "no plan" tile.
      expect(state.isPromotional, false);
      expect(state.isTrial, false);
    });
  });

  group('mapStatusV2ToState — cancel_at_period_end mirroring (D7/#6)', () {
    test(
      'unsubscribeDetectedAt mirrors cancelAtPeriodEnd (true -> endsAt)',
      () {
        final state =
            mapStatusV2ToState(
                  status(
                    winning: WinningSummaryV2(
                      type: "paid",
                      status: "active",
                      endsAt: endsAt,
                      cancelAtPeriodEnd: true,
                      planId: "year",
                    ),
                  ),
                  stripeAppId: stripeAppId,
                )
                as SubscriptionActive;
        expect(state.cancelAtPeriodEnd, true);
        expect(state.unsubscribeDetectedAt, endsAt);
      },
    );

    test('unsubscribeDetectedAt is null when not cancelling', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: WinningSummaryV2(
                    type: "paid",
                    status: "active",
                    endsAt: endsAt,
                    cancelAtPeriodEnd: false,
                    planId: "year",
                  ),
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.unsubscribeDetectedAt, isNull);
    });
  });

  group('mapStatusV2ToState — billable individual type (finding #1)', () {
    test('individual -> isPromotional false, isTrial false (billable)', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "individual",
                    status: "active",
                    planId: "month",
                  ),
                  entitlements: const [
                    EntitlementV2(
                      entitlementRef: "ent_ind",
                      type: "individual",
                      cancelable: true,
                      status: "active",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      // A paying individual-plan user must NOT be classified as promotional
      // (that would skip their account-delete warning + paid tile).
      expect(state.isPromotional, false);
      expect(state.isTrial, false);
      expect(state.subscriptionId, "month");
      expect(state.cancelable, true);
    });

    test('individual with null planId still not promotional (paid tile)', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "individual",
                    status: "active",
                  ),
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.isPromotional, false);
      expect(state.isTrial, false);
      expect(state.subscriptionId, stripeAppId);
    });
  });

  group('mapStatusV2ToState — promotional shapes (I11)', () {
    test('comp -> isPromotional true, isTrial false, not cancelable', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "comp",
                    status: "active",
                  ),
                  entitlements: const [
                    EntitlementV2(
                      entitlementRef: "ent_comp",
                      type: "comp",
                      cancelable: false,
                      status: "active",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.isPromotional, true);
      expect(state.isTrial, false);
      expect(state.cancelable, false);
      expect(state.entitlementRef, isNull);
    });

    test('seat -> isPromotional true, not cancelable', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "seat",
                    status: "active",
                  ),
                  entitlements: const [
                    EntitlementV2(
                      entitlementRef: "ent_seat",
                      type: "seat",
                      cancelable: false,
                      status: "active",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.isPromotional, true);
      expect(state.cancelable, false);
    });

    test('trial -> isTrial true, isPromotional true, not cancelable', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: WinningSummaryV2(
                    type: "trial",
                    status: "active",
                    endsAt: endsAt,
                  ),
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.isTrial, true);
      expect(state.isPromotional, true);
      expect(state.cancelable, false);
      expect(state.entitlementRef, isNull);
      // An active trial has no catalog plan, so the mapper resolves the
      // subscriptionId to the [kV2TrialId] sentinel (NOT stripeAppId) so the
      // controller `subscription` getter resolves the synthesized trial tile
      // (B2 wiring) and the trial copy / hasFreeTrial render.
      expect(state.subscriptionId, kV2TrialId);
    });

    test(
      'active trial resolves subscriptionId to the trial sentinel even when a '
      'planId is present',
      () {
        // Defensive: whatever the winning carries, a trial must never resolve
        // to a paid product tile.
        final state =
            mapStatusV2ToState(
                  status(
                    winning: WinningSummaryV2(
                      type: "trial",
                      status: "active",
                      endsAt: endsAt,
                      planId: "month",
                    ),
                  ),
                  stripeAppId: stripeAppId,
                )
                as SubscriptionActive;
        expect(state.isTrial, true);
        expect(state.subscriptionId, kV2TrialId);
      },
    );
  });

  group('mapStatusV2ToState — cancel entitlement selection (I10)', () {
    test('skips a non-cancelable row', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "paid",
                    status: "active",
                    planId: "month",
                  ),
                  entitlements: const [
                    EntitlementV2(
                      entitlementRef: "ent_x",
                      type: "paid",
                      cancelable: false,
                      status: "active",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.cancelable, false);
      expect(state.entitlementRef, isNull);
    });

    test('skips a row already set to cancel at period end', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "paid",
                    status: "active",
                    planId: "month",
                  ),
                  entitlements: const [
                    EntitlementV2(
                      entitlementRef: "ent_x",
                      type: "paid",
                      cancelable: true,
                      cancelAtPeriodEnd: true,
                      status: "active",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.cancelable, false);
      expect(state.entitlementRef, isNull);
    });

    test('single cancelable row is selected (fallback, no winning ref)', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "paid",
                    status: "active",
                    planId: "month",
                  ),
                  entitlements: const [
                    EntitlementV2(
                      entitlementRef: "ent_only",
                      type: "paid",
                      cancelable: true,
                      status: "active",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.cancelable, true);
      expect(state.entitlementRef, "ent_only");
    });

    test('winning.entitlementRef is THE cancel target when present', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "paid",
                    status: "active",
                    planId: "month",
                    entitlementRef: "ent_win",
                  ),
                  entitlements: const [
                    // Another cancelable row exists; the named winner still wins.
                    EntitlementV2(
                      entitlementRef: "ent_aaa",
                      type: "paid",
                      cancelable: true,
                      status: "active",
                    ),
                    EntitlementV2(
                      entitlementRef: "ent_win",
                      type: "paid",
                      cancelable: true,
                      status: "active",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.entitlementRef, "ent_win");
      expect(state.cancelable, true);
    });

    test('winning.entitlementRef naming a non-cancelable row -> no cancel', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "paid",
                    status: "active",
                    planId: "month",
                    entitlementRef: "ent_win",
                  ),
                  entitlements: const [
                    EntitlementV2(
                      entitlementRef: "ent_win",
                      type: "paid",
                      cancelable: false,
                      status: "active",
                    ),
                    // A different cancelable row must NOT be substituted.
                    EntitlementV2(
                      entitlementRef: "ent_other",
                      type: "paid",
                      cancelable: true,
                      status: "active",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      expect(state.cancelable, false);
      expect(state.entitlementRef, isNull);
    });

    test(
      'ambiguous (>1 cancelable, no winning ref, no discriminator) -> no cancel',
      () {
        // Never risk canceling the wrong subscription: with two indistinguishable
        // cancelable rows and nothing to pick by, offer NO cancel target.
        final entitlements = [
          const EntitlementV2(
            entitlementRef: "ent_zzz",
            type: "paid",
            cancelable: true,
            status: "active",
          ),
          const EntitlementV2(
            entitlementRef: "ent_aaa",
            type: "paid",
            cancelable: true,
            status: "active",
          ),
        ];
        final state =
            mapStatusV2ToState(
                  status(
                    winning: const WinningSummaryV2(
                      type: "paid",
                      status: "active",
                      planId: "month",
                    ),
                    entitlements: entitlements,
                  ),
                  stripeAppId: stripeAppId,
                )
                as SubscriptionActive;
        expect(state.cancelable, false);
        expect(state.entitlementRef, isNull);
      },
    );

    test('prefers the row matching the winning sourceSubscriptionId', () {
      final state =
          mapStatusV2ToState(
                status(
                  winning: const WinningSummaryV2(
                    type: "paid",
                    status: "active",
                    planId: "month",
                    sourceSubscriptionId: "sub_win",
                  ),
                  entitlements: const [
                    EntitlementV2(
                      entitlementRef: "ent_aaa",
                      type: "paid",
                      cancelable: true,
                      status: "active",
                      sourceSubscriptionId: "sub_other",
                    ),
                    EntitlementV2(
                      entitlementRef: "ent_zzz",
                      type: "paid",
                      cancelable: true,
                      status: "active",
                      sourceSubscriptionId: "sub_win",
                    ),
                  ],
                ),
                stripeAppId: stripeAppId,
              )
              as SubscriptionActive;
      // ent_zzz wins on the source-id preference despite a higher ref.
      expect(state.entitlementRef, "ent_zzz");
    });
  });
}
