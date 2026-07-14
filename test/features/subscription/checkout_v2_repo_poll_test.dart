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
  // body is captured to assert the money-safety contract: EXACTLY {"planId"},
  // no injected user context (I1).
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
      'creating -> created loops, honors retryAfterSeconds, returns url',
      () async {
        final req = requestsReturning([
          {"status": "creating", "sessionUrl": null, "retryAfterSeconds": 2},
          {
            "status": "created",
            "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_ok",
          },
        ]);

        final url = await CheckoutV2Repo.checkoutWith(
          req,
          "month",
          url: checkoutUrl,
          delay: fakeDelay,
        );

        expect(url, "https://checkout.stripe.com/c/pay/cs_test_ok");
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
}
