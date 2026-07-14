import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo/billing_portal_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Returned (as the `Result.error`) when `/subscription/billing_portal` answers
/// 404 `{"detail": "No billing account"}` — the user has no canonical Stripe
/// customer (e.g. never purchased on web). Typed so the UI can HIDE the manage
/// entry rather than surfacing a transient-error retry.
class NoBillingAccountException implements Exception {
  const NoBillingAccountException();

  @override
  String toString() => "NoBillingAccountException";
}

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

/// Mints a short-lived Stripe billing-portal URL for the user's CANONICAL
/// customer (choreo `BillingPortalSessionResponse`, field `url`). Portal URLs
/// are short-lived, so callers mint on click and open immediately. A user with
/// no canonical customer -> [NoBillingAccountException] (hide the manage entry).
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

    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    final future = getWith(req);
    _cache[userID] = BillingPortalCacheEntry(
      future: future,
      timestamp: DateTime.now(),
    );
    return future;
  }

  /// The transport core, decoupled from `MatrixState` so the typed-404 and
  /// success paths are unit-testable with an injected [Requests] (MockClient).
  @visibleForTesting
  static Future<Result<BillingPortalResponse>> getWith(
    Requests req, {
    String? url,
  }) async {
    try {
      final Response res = await req.get(url: url ?? PApiUrls.billingPortal);
      // `req.get` throws on >= 400; only a 2xx body reaches here.
      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );
      return Result.value(BillingPortalResponse.fromJson(json));
    } on ChoreoException catch (e) {
      if (e.response.statusCode == 404) {
        // No canonical Stripe customer — a typed, non-retryable outcome.
        return Result.error(const NoBillingAccountException());
      }
      ErrorHandler.logError(e: e.errorMessage, data: {});
      return Result.error(e);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return Result.error(e);
    }
  }
}
