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

/// Mints a short-lived Stripe billing-portal URL for the user's CANONICAL
/// customer (choreo `BillingPortalSessionResponse`, field `url`).
///
/// Portal session URLs are SHORT-LIVED by design: mint on click, open
/// immediately, and NEVER cache the minted URL — every call performs a fresh
/// request. The only sharing is in-flight dedupe (two overlapping taps ride
/// the same request), and the in-flight entry is evicted as soon as the
/// request completes, success OR failure — a transient error is never cached,
/// so the next tap retries cleanly. A user with no canonical customer ->
/// [NoBillingAccountException] (hide the manage entry).
class BillingPortalRepo {
  static final Map<String, Future<Result<BillingPortalResponse>>> _inflight =
      {};

  static Future<Result<BillingPortalResponse>> get(String userID) {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    return getWith(req, dedupeKey: userID);
  }

  /// The transport core, decoupled from `MatrixState` so the dedupe/no-cache
  /// behavior and the typed-404 path are unit-testable with an injected
  /// [Requests] (MockClient).
  @visibleForTesting
  static Future<Result<BillingPortalResponse>> getWith(
    Requests req, {
    String? url,
    String dedupeKey = "portal",
  }) {
    final inflight = _inflight[dedupeKey];
    if (inflight != null) return inflight;

    // _fetch never throws (failures come back as Result.error), so
    // whenComplete is the `finally` that guarantees eviction either way.
    // NOTE: the callback MUST have a block body — `Map.remove` returns the
    // evicted value (this very future), and whenComplete AWAITS a returned
    // future, which would deadlock the future on itself.
    final future = _fetch(req, url: url).whenComplete(() {
      _inflight.remove(dedupeKey);
    });
    _inflight[dedupeKey] = future;
    return future;
  }

  static Future<Result<BillingPortalResponse>> _fetch(
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
      // ONLY a 404 whose detail is exactly "No billing account" is the
      // no-portal signal (no canonical Stripe customer). Any OTHER 404
      // (route/deploy mismatch, FastAPI "Not Found") is a real integration
      // failure and must surface as the ChoreoException — never masked as
      // "management unavailable" (finding #4).
      if (e.response.statusCode == 404 && e.message == "No billing account") {
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
