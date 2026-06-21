import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/features/subscription/repo/payment_link_request.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PaymentLinkRepo {
  static final Map<String, Future<Result<String>>> _inflightCache = {};

  static Future<Result<String>> get(PaymentLinkRequest request) async {
    final cached = _inflightCache[request.storageKey];
    if (cached != null) {
      return cached;
    }

    final future = _fetch(request);

    _inflightCache[request.storageKey] = future;
    final response = await future;
    _inflightCache.remove(request.storageKey);

    return response;
  }

  static Future<Result<String>> _fetch(PaymentLinkRequest request) async {
    try {
      final Requests req = Requests(
        choreoApiKey: Environment.choreoApiKey,
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );
      final String reqUrl = Uri.encodeFull(
        "${PApiUrls.paymentLink}?duration=${request.duration.name}&redeem=${request.isPromo}",
      );
      final Response res = await req.get(url: reqUrl);
      final json = jsonDecode(res.body);
      String paymentLink = json["link"]["url"];

      final String? email =
          await MatrixState.pangeaController.userController.userEmail;

      if (email != null) {
        paymentLink += "?prefilled_email=${Uri.encodeComponent(email)}";
      }

      return Result.value(paymentLink);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }
}
