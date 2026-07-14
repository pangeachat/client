import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/subscription/repo/checkout_v2_repo.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';

void main() {
  // A literal checkout URL is passed to `checkoutWith` so the pollable core is
  // exercised without touching `Environment` (GetStorage/dotenv are not
  // initialized under `flutter test`).
  const checkoutUrl = "https://example.test/subscription/checkout";

  // Bounded-poll behavior (I3), driven through the testable `checkoutWith` core
  // with a MockClient transport + a fake delay seam (no real waits). Each POST
  // body is captured to assert the money-safety contract: EXACTLY {"planId"}
  // (plus an optional "promoCode"), no injected user context (I1).
  group('CheckoutV2Repo.checkoutWith poll', () {
    late List<Map<String, dynamic>> sentBodies;
    late List<Duration> observedDelays;

    setUp(() {
      sentBodies = [];
      observedDelays = [];
    });

    Future<void> fakeDelay(Duration d) async => observedDelays.add(d);

    Requests requestsReturning(List<Map<String, dynamic>> responses) {
      var call = 0;
      final client = MockClient((request) async {
        sentBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        // creating -> 202, resolved -> 200 (mirrors the choreo status codes).
        final body =
            responses[call < responses.length ? call : responses.length - 1];
        call++;
        final statusCode = body["status"] == "creating" ? 202 : 200;
        return http.Response(jsonEncode(body), statusCode);
      });
      return Requests(accessToken: "token", client: client);
    }

    test(
      'creating -> created loops, honors retryAfterSeconds, returns response',
      () async {
        final req = requestsReturning([
          {"status": "creating", "sessionUrl": null, "retryAfterSeconds": 2},
          {
            "status": "created",
            "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_ok",
          },
        ]);

        final res = await CheckoutV2Repo.checkoutWith(
          req,
          "month",
          url: checkoutUrl,
          delay: fakeDelay,
        );

        expect(res.sessionUrl, "https://checkout.stripe.com/c/pay/cs_test_ok");
        // One wait, of exactly the server-supplied retryAfterSeconds.
        expect(observedDelays, [const Duration(seconds: 2)]);
        expect(sentBodies.length, 2);
      },
    );

    test(
      'every POST body is exactly {planId} — no injected context (I1)',
      () async {
        final req = requestsReturning([
          {"status": "creating", "retryAfterSeconds": 2},
          {"status": "reused", "sessionUrl": "https://s/cs_test_reuse"},
        ]);

        await CheckoutV2Repo.checkoutWith(
          req,
          "year",
          url: checkoutUrl,
          delay: fakeDelay,
        );

        for (final body in sentBodies) {
          expect(body, {"planId": "year"});
          expect(body.containsKey("user_cefr"), false);
          expect(body.containsKey("user_gender"), false);
        }
      },
    );

    test('falls back to a 2s delay when retryAfterSeconds is absent', () async {
      final req = requestsReturning([
        {"status": "creating"},
        {"status": "created", "sessionUrl": "https://s/cs_test_fallback"},
      ]);

      await CheckoutV2Repo.checkoutWith(
        req,
        "month",
        url: checkoutUrl,
        delay: fakeDelay,
      );
      expect(observedDelays, [CheckoutV2Repo.fallbackDelay]);
    });

    test('creating forever -> throws after the attempt cap', () async {
      final req = requestsReturning([
        {"status": "creating", "retryAfterSeconds": 2},
      ]);

      await expectLater(
        CheckoutV2Repo.checkoutWith(
          req,
          "month",
          url: checkoutUrl,
          delay: fakeDelay,
        ),
        throwsA(isA<CheckoutException>()),
      );
      // 5 attempts total, 4 waits between them (the 5th attempt does not wait).
      expect(sentBodies.length, CheckoutV2Repo.maxAttempts);
      expect(observedDelays.length, CheckoutV2Repo.maxAttempts - 1);
    });

    test('resolved without a sessionUrl throws (malformed terminal)', () async {
      final req = requestsReturning([
        {"status": "created", "sessionUrl": null},
      ]);

      await expectLater(
        CheckoutV2Repo.checkoutWith(
          req,
          "month",
          url: checkoutUrl,
          delay: fakeDelay,
        ),
        throwsA(isA<CheckoutException>()),
      );
    });

    test('stops polling once the cumulative wait budget is exhausted', () async {
      // A large retryAfterSeconds trips the ~15s total-wait cap before the
      // attempt cap: first wait 10s (<=15 issued), second would push to 20s and
      // is refused, so it throws after 2 attempts / 1 wait.
      final req = requestsReturning([
        {"status": "creating", "retryAfterSeconds": 10},
      ]);

      await expectLater(
        CheckoutV2Repo.checkoutWith(
          req,
          "month",
          url: checkoutUrl,
          delay: fakeDelay,
        ),
        throwsA(isA<CheckoutException>()),
      );
      expect(observedDelays, [const Duration(seconds: 10)]);
      expect(sentBodies.length, 2);
    });
  });

  // Discount-checkout behavior: the optional promoCode in the body, the echoed
  // appliedPromoCode, and the typed promo-rejection surface Gabby's UI consumes.
  group('CheckoutV2Repo.checkoutWith discount', () {
    const checkoutUrl = "https://example.test/subscription/checkout";
    late List<Map<String, dynamic>> sentBodies;

    setUp(() => sentBodies = []);

    Requests requestsReturning({
      required Map<String, dynamic> body,
      int statusCode = 200,
    }) {
      final client = MockClient((request) async {
        sentBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(body), statusCode);
      });
      return Requests(accessToken: "token", client: client);
    }

    // Emits a raw error response with the given `detail` (object or list) so
    // `Requests.handleError` rethrows the raw response — the 422 shapes.
    Requests requestsErroring({required Object detail, int statusCode = 422}) {
      final client = MockClient((request) async {
        sentBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({"detail": detail}), statusCode);
      });
      return Requests(accessToken: "token", client: client);
    }

    test('promoCode is sent as exactly {planId, promoCode}', () async {
      final req = requestsReturning(
        body: {
          "status": "created",
          "sessionUrl": "https://s/cs_test_disc",
          "appliedPromoCode": "WELCOME50",
        },
      );

      await CheckoutV2Repo.checkoutWith(
        req,
        "month",
        promoCode: "WELCOME50",
        url: checkoutUrl,
      );

      expect(sentBodies.single, {"planId": "month", "promoCode": "WELCOME50"});
    });

    test('an empty promoCode is omitted from the body', () async {
      final req = requestsReturning(
        body: {"status": "created", "sessionUrl": "https://s/cs_test_ok"},
      );

      await CheckoutV2Repo.checkoutWith(
        req,
        "month",
        promoCode: "",
        url: checkoutUrl,
      );

      expect(sentBodies.single, {"planId": "month"});
    });

    test('a whitespace-only promoCode is omitted from the body', () async {
      final req = requestsReturning(
        body: {"status": "created", "sessionUrl": "https://s/cs_test_ok"},
      );

      await CheckoutV2Repo.checkoutWith(
        req,
        "month",
        promoCode: "   ",
        url: checkoutUrl,
      );

      expect(sentBodies.single, {"planId": "month"});
    });

    test('a promoCode with surrounding whitespace is sent trimmed', () async {
      final req = requestsReturning(
        body: {
          "status": "created",
          "sessionUrl": "https://s/cs_test_disc",
          "appliedPromoCode": "WELCOME50",
        },
      );

      await CheckoutV2Repo.checkoutWith(
        req,
        "month",
        promoCode: "  WELCOME50  ",
        url: checkoutUrl,
      );

      expect(sentBodies.single, {"planId": "month", "promoCode": "WELCOME50"});
    });

    test('exposes appliedPromoCode from the resolved response', () async {
      final req = requestsReturning(
        body: {
          "status": "reused",
          "sessionUrl": "https://s/cs_test_reuse",
          // Reuse ignores the requested code; the STORED code echoes back.
          "appliedPromoCode": "EXISTINGCODE",
        },
      );

      final res = await CheckoutV2Repo.checkoutWith(
        req,
        "month",
        promoCode: "WELCOME50",
        url: checkoutUrl,
      );

      expect(res.appliedPromoCode, "EXISTINGCODE");
      expect(res.sessionUrl, "https://s/cs_test_reuse");
    });

    test(
      'promo_not_applicable 422 -> PromoNotApplicableException, each reason typed',
      () async {
        const wireToReason = <String, CheckoutPromoRejectionReason>{
          "not_found_or_inactive":
              CheckoutPromoRejectionReason.notFoundOrInactive,
          "wrong_customer": CheckoutPromoRejectionReason.wrongCustomer,
          "expired": CheckoutPromoRejectionReason.expired,
          "max_redeemed": CheckoutPromoRejectionReason.maxRedeemed,
          "coupon_invalid": CheckoutPromoRejectionReason.couponInvalid,
          "wrong_plan": CheckoutPromoRejectionReason.wrongPlan,
          "below_minimum": CheckoutPromoRejectionReason.belowMinimum,
          "currency_mismatch": CheckoutPromoRejectionReason.currencyMismatch,
          "rejected_by_stripe": CheckoutPromoRejectionReason.rejectedByStripe,
        };

        for (final entry in wireToReason.entries) {
          final req = requestsErroring(
            detail: {"code": "promo_not_applicable", "reason": entry.key},
          );

          await expectLater(
            CheckoutV2Repo.checkoutWith(
              req,
              "month",
              promoCode: "BADCODE",
              url: checkoutUrl,
            ),
            throwsA(
              isA<PromoNotApplicableException>()
                  .having((e) => e.reason, 'reason', entry.value)
                  .having((e) => e.rawReason, 'rawReason', entry.key),
            ),
          );
        }
      },
    );

    test(
      'an unmodeled promo reason maps to unknown (never throws on map)',
      () async {
        final req = requestsErroring(
          detail: {
            "code": "promo_not_applicable",
            "reason": "brand_new_reason",
          },
        );

        await expectLater(
          CheckoutV2Repo.checkoutWith(
            req,
            "month",
            promoCode: "BADCODE",
            url: checkoutUrl,
          ),
          throwsA(
            isA<PromoNotApplicableException>().having(
              (e) => e.reason,
              'reason',
              CheckoutPromoRejectionReason.unknown,
            ),
          ),
        );
      },
    );

    test(
      'schema-shaped 422 (list detail) -> CheckoutException, NOT promo rejection',
      () async {
        final req = requestsErroring(
          detail: [
            {
              "type": "extra_forbidden",
              "loc": ["body", "surprise"],
              "msg": "Extra inputs are not permitted",
            },
          ],
        );

        await expectLater(
          CheckoutV2Repo.checkoutWith(
            req,
            "month",
            promoCode: "WELCOME50",
            url: checkoutUrl,
          ),
          throwsA(
            allOf(
              isA<CheckoutException>(),
              isNot(isA<PromoNotApplicableException>()),
            ),
          ),
        );
      },
    );

    test(
      'a string-detail error (e.g. 409) surfaces as ChoreoException',
      () async {
        final req = requestsErroring(
          detail: "already_subscribed",
          statusCode: 409,
        );

        await expectLater(
          CheckoutV2Repo.checkoutWith(req, "month", url: checkoutUrl),
          throwsA(isA<ChoreoException>()),
        );
      },
    );
  });
}
