import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/features/subscription/repo/billing_portal_response.dart';
import 'package:fluffychat/widgets/matrix.dart';

class BillingPortalCacheEntry {
  final Future<Result<BillingPortalResponse>> future;
  final DateTime timestamp;

  const BillingPortalCacheEntry({
    required this.future,
    required this.timestamp,
  });

  static const Duration _cacheDuration = Duration(minutes: 10);

  bool get isExpired =>
      timestamp.isBefore(DateTime.now().subtract(_cacheDuration));
}

class BillingPortalRepo {
  static final Map<String, BillingPortalCacheEntry> _cache = {};

  static Future<Result<BillingPortalResponse>> get(String userID) async {
    final cached = _cache[userID];
    if (cached != null) {
      if (cached.isExpired) {
        _cache.remove(userID);
      } else {
        return cached.future;
      }
    }

    final future = _fetch();
    _cache[userID] = BillingPortalCacheEntry(
      future: future,
      timestamp: DateTime.now(),
    );
    final result = await future;
    return result;
  }

  static Future<Result<BillingPortalResponse>> _fetch() async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        choreoApiKey: Environment.choreoApiKey,
      );
      final Response res = await req.get(url: PApiUrls.billingPortal);

      if (res.statusCode != 200) {
        throw res;
      }

      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      final response = BillingPortalResponse.fromJson(json);
      return Result.value(response);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return Result.error(e);
    }
  }
}
