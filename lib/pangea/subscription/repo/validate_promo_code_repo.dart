import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/subscription/repo/validate_promo_code_request.dart';
import 'package:fluffychat/pangea/subscription/repo/validate_promo_code_response.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ValidatePromoCodeRepo {
  static final Map<String, Future<Result<ValidatePromoCodeResponse>>>
  _inflightCache = {};

  static Future<Result<ValidatePromoCodeResponse>> get(
    ValidatePromoCodeRequest request,
  ) async {
    final cached = _inflightCache[request.storageKey];
    if (cached != null) {
      return cached;
    }

    final future = _fetch(request);

    _inflightCache[request.storageKey] = future;
    final result = await future;
    _inflightCache.remove(request.storageKey);

    return result;
  }

  static Future<Result<ValidatePromoCodeResponse>> _fetch(
    ValidatePromoCodeRequest request,
  ) async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        choreoApiKey: Environment.choreoApiKey,
      );
      final Response res = await req.post(
        url: PApiUrls.validatePromoCode,
        body: request.toJson(),
      );

      if (res.statusCode != 200) {
        throw res;
      }

      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      final response = ValidatePromoCodeResponse.fromJson(json);
      return Result.value(response);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }
}
