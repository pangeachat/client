import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/subscription/repo/billing_portal_repo.dart';
import 'package:fluffychat/features/subscription/repo/billing_portal_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';

void main() {
  const portalUrl = "https://example.test/subscription/billing_portal";

  group('BillingPortalResponse.fromJson', () {
    test('parses the {url} envelope', () {
      final res = BillingPortalResponse.fromJson({
        "url": "https://billing.stripe.com/p/session_123",
      });
      expect(res.url, "https://billing.stripe.com/p/session_123");
      expect(res.toJson(), {"url": "https://billing.stripe.com/p/session_123"});
    });
  });

  group('BillingPortalRepo.getWith', () {
    Requests requestsWith(int statusCode, Object body) {
      final client = MockClient((request) async {
        return http.Response(jsonEncode(body), statusCode);
      });
      return Requests(accessToken: "token", client: client);
    }

    test('200 -> Result.value carrying the portal url', () async {
      final req = requestsWith(200, {
        "url": "https://billing.stripe.com/p/session_ok",
      });

      final result = await BillingPortalRepo.getWith(
        req,
        url: portalUrl,
        dedupeKey: "t-ok",
      );

      expect(result.isError, false);
      expect(
        result.asValue!.value.url,
        "https://billing.stripe.com/p/session_ok",
      );
    });

    test(
      '404 "No billing account" -> typed NoBillingAccountException (hide manage)',
      () async {
        final req = requestsWith(404, {"detail": "No billing account"});

        final result = await BillingPortalRepo.getWith(
          req,
          url: portalUrl,
          dedupeKey: "t-404",
        );

        expect(result.isError, true);
        expect(result.asError!.error, isA<NoBillingAccountException>());
      },
    );

    test('a non-404 error is NOT a NoBillingAccountException', () async {
      final req = requestsWith(500, {"detail": "internal error"});

      final result = await BillingPortalRepo.getWith(
        req,
        url: portalUrl,
        dedupeKey: "t-500",
      );

      expect(result.isError, true);
      expect(result.asError!.error, isNot(isA<NoBillingAccountException>()));
    });

    // Portal session URLs are SHORT-LIVED and minted on click — the repo must
    // never cache them, and must NEVER cache a transient error (a single 5xx
    // must not poison manage-billing).
    test('an error is never cached — the next call retries and succeeds',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(jsonEncode({"detail": "upstream down"}), 502);
        }
        return http.Response(
          jsonEncode({"url": "https://billing.stripe.com/p/session_retry"}),
          200,
        );
      });
      final req = Requests(accessToken: "token", client: client);

      final first = await BillingPortalRepo.getWith(
        req,
        url: portalUrl,
        dedupeKey: "t-retry",
      );
      expect(first.isError, true);

      final second = await BillingPortalRepo.getWith(
        req,
        url: portalUrl,
        dedupeKey: "t-retry",
      );
      expect(second.isError, false);
      expect(
        second.asValue!.value.url,
        "https://billing.stripe.com/p/session_retry",
      );
      expect(calls, 2);
    });

    test('two CONCURRENT calls dedupe to a single HTTP request', () async {
      var calls = 0;
      final gate = Completer<void>();
      final client = MockClient((request) async {
        calls++;
        await gate.future;
        return http.Response(
          jsonEncode({"url": "https://billing.stripe.com/p/session_once"}),
          200,
        );
      });
      final req = Requests(accessToken: "token", client: client);

      final f1 = BillingPortalRepo.getWith(
        req,
        url: portalUrl,
        dedupeKey: "t-dedupe",
      );
      final f2 = BillingPortalRepo.getWith(
        req,
        url: portalUrl,
        dedupeKey: "t-dedupe",
      );
      gate.complete();

      final results = await Future.wait([f1, f2]);
      expect(calls, 1);
      expect(
        results[0].asValue!.value.url,
        "https://billing.stripe.com/p/session_once",
      );
      expect(
        results[1].asValue!.value.url,
        "https://billing.stripe.com/p/session_once",
      );
    });

    test('SEQUENTIAL calls mint a FRESH session each time (no URL cache)',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({"url": "https://billing.stripe.com/p/session_$calls"}),
          200,
        );
      });
      final req = Requests(accessToken: "token", client: client);

      final first = await BillingPortalRepo.getWith(
        req,
        url: portalUrl,
        dedupeKey: "t-fresh",
      );
      final second = await BillingPortalRepo.getWith(
        req,
        url: portalUrl,
        dedupeKey: "t-fresh",
      );

      expect(calls, 2);
      expect(
        first.asValue!.value.url,
        "https://billing.stripe.com/p/session_1",
      );
      expect(
        second.asValue!.value.url,
        "https://billing.stripe.com/p/session_2",
      );
    });
  });
}
