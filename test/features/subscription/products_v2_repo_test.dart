import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/subscription/repo/products_v2_repo.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';

// A /products FETCH FAILURE must NOT be swallowed into an empty catalog (which
// would strand a buyer on a 503 with "no plans"). getWith distinguishes a real
// empty 200 (return empty) from a transport/5xx/malformed failure (throw), so
// the controller can set a retryable error state instead (finding #2).
void main() {
  const productsUrl = "https://example.test/subscription/products";

  Requests requestsWith(int statusCode, String body) {
    final client = MockClient((request) async => http.Response(body, statusCode));
    return Requests(accessToken: "token", client: client);
  }

  test('200 with plans -> parsed catalog (non-empty)', () async {
    final req = requestsWith(
      200,
      jsonEncode({
        "plans": [
          {
            "planId": "month",
            "amount": 999,
            "currency": "usd",
            "interval": "month",
            "interval_count": 1,
          },
        ],
      }),
    );

    final res = await ProductsV2Repo.getWith(req, url: productsUrl);
    expect(res.plans, hasLength(1));
    expect(res.plans.single.planId, "month");
  });

  test('200 with an EMPTY plans list -> empty catalog (NOT an error)', () async {
    final req = requestsWith(200, jsonEncode({"plans": []}));

    final res = await ProductsV2Repo.getWith(req, url: productsUrl);
    expect(res.plans, isEmpty);
  });

  test('503 products_unavailable -> THROWS (fetch failure, not empty)', () async {
    final req = requestsWith(503, jsonEncode({"detail": "products_unavailable"}));

    await expectLater(
      ProductsV2Repo.getWith(req, url: productsUrl),
      throwsA(anything),
    );
  });

  test('a malformed 200 body -> THROWS (fetch failure, not empty)', () async {
    final req = requestsWith(200, "<html>not json</html>");

    await expectLater(
      ProductsV2Repo.getWith(req, url: productsUrl),
      throwsA(anything),
    );
  });
}
