import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/subscription/repo/payment_history_response.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PaymentHistoryCacheEntry {
  final Future<Result<PaymentHistoryResponse>> future;
  final DateTime timestamp;

  const PaymentHistoryCacheEntry({
    required this.future,
    required this.timestamp,
  });

  static const Duration _cacheDuration = Duration(minutes: 10);

  bool get isExpired =>
      timestamp.isBefore(DateTime.now().subtract(_cacheDuration));
}

class PaymentHistoryRepo {
  static final Map<String, PaymentHistoryCacheEntry> _cache = {};

  static Future<Result<PaymentHistoryResponse>> get(String userID) async {
    final cached = _cache[userID];
    if (cached != null) {
      if (cached.isExpired) {
        _cache.remove(userID);
      } else {
        return cached.future;
      }
    }

    final future = _fetch();

    _cache[userID] = PaymentHistoryCacheEntry(
      future: future,
      timestamp: DateTime.now(),
    );

    final result = await future;
    return result;
  }

  static Future<Result<PaymentHistoryResponse>> _fetch() async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        choreoApiKey: Environment.choreoApiKey,
      );
      final Response res = await req.get(url: PApiUrls.paymentHistory);

      if (res.statusCode != 200) {
        throw res;
      }

      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      final response = PaymentHistoryResponse.fromJson(json);
      return Result.value(response);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return Result.error(e);
    }
  }
}
