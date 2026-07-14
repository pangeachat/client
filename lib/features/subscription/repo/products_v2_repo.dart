import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/subscription/models/products_v2_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Fetches the Subscriptions-v2 `/subscription/products` storefront.
///
/// I9 (finding #8): this is a SEPARATE repo from `AllProductsRepo` with NO
/// shared cache — the RC and v2 catalogs must never poison each other across
/// the flag flip. It fetches fresh every call (the catalog is small and read at
/// init only), so a flip cannot serve a stale cross-schema payload.
///
/// Failure semantics (finding #2): the repo distinguishes a REAL empty catalog
/// (a 200 with `plans: []`) from a FETCH FAILURE (transport error, 5xx / 503
/// `products_unavailable`, or a malformed body). On success it returns the
/// parsed response — possibly with an empty `plans` list. On a fetch failure it
/// THROWS, so the controller sets a retryable error state instead of silently
/// building an empty sellable catalog that would strand a buyer on a 503.
class ProductsV2Repo {
  static Future<ProductsV2Response> get({http.Client? client}) {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
      client: client,
    );
    return getWith(req);
  }

  /// The transport core, decoupled from `MatrixState` so the throw-on-failure
  /// vs empty-200 distinction is unit-testable with an injected [Requests]
  /// (MockClient). `req.get` throws (ChoreoException) on >= 400; a malformed
  /// body throws while decoding — both propagate as the fetch-failure signal.
  @visibleForTesting
  static Future<ProductsV2Response> getWith(Requests req, {String? url}) async {
    final http.Response res = await req.get(
      url: url ?? PApiUrls.subscriptionProducts,
    );
    final Map<String, dynamic> json =
        jsonDecode(res.body) as Map<String, dynamic>;
    return ProductsV2Response.fromJson(json);
  }
}
