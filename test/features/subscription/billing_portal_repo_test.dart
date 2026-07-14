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

      final result = await BillingPortalRepo.getWith(req, url: portalUrl);

      expect(result.isError, false);
      expect(result.asValue!.value.url, "https://billing.stripe.com/p/session_ok");
    });

    test(
      '404 "No billing account" -> typed NoBillingAccountException (hide manage)',
      () async {
        final req = requestsWith(404, {"detail": "No billing account"});

        final result = await BillingPortalRepo.getWith(req, url: portalUrl);

        expect(result.isError, true);
        expect(result.asError!.error, isA<NoBillingAccountException>());
      },
    );

    test('a non-404 error is NOT a NoBillingAccountException', () async {
      final req = requestsWith(500, {"detail": "internal error"});

      final result = await BillingPortalRepo.getWith(req, url: portalUrl);

      expect(result.isError, true);
      expect(result.asError!.error, isNot(isA<NoBillingAccountException>()));
    });
  });
}
