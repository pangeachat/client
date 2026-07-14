import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/subscription/models/products_v2_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Fetches the Subscriptions-v2 `/subscription/products` storefront.
///
/// I9 (finding #8): this is a SEPARATE repo from `AllProductsRepo` with NO
/// shared cache — the RC and v2 catalogs must never poison each other across
/// the flag flip. It fetches fresh every call (the catalog is small and read at
/// init only), so a flip cannot serve a stale cross-schema payload.
class ProductsV2Repo {
  static Future<ProductsV2Response?> get({http.Client? client}) async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        client: client,
      );
      final http.Response res = await req.get(
        url: PApiUrls.subscriptionProducts,
      );
      final Map<String, dynamic> json =
          jsonDecode(res.body) as Map<String, dynamic>;
      return ProductsV2Response.fromJson(json);
    } catch (err, s) {
      if (err is ChoreoException) {
        ErrorHandler.logError(e: err.errorMessage, data: {});
      } else {
        ErrorHandler.logError(e: err, s: s, data: {});
      }
      return null;
    }
  }
}
