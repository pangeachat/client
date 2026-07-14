import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/subscription/models/checkout_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Raised when a `/subscription/checkout` flow cannot be resolved to a session
/// URL — a malformed terminal response, an unexpected status, the bounded poll
/// giving up, or a schema-shaped 422 (a client bug, distinct from the business
/// promo rejection below). User-visible (I3).
class CheckoutException implements Exception {
  final String message;
  const CheckoutException(this.message);

  @override
  String toString() => "CheckoutException: $message";
}

/// The nine server-side reasons `/subscription/checkout` rejects a REQUESTED
/// promo code (the `promo_not_applicable` 422). The first eight come from the
/// choreo promo resolver; [rejectedByStripe] is emitted when Stripe re-validates
/// and rejects the code at Session.create (defense-in-depth). [unknown] is a
/// forward-compatible fallback for a reason string this client does not model
/// yet — surface it as a generic "code could not be applied" message.
enum CheckoutPromoRejectionReason {
  notFoundOrInactive,
  wrongCustomer,
  expired,
  maxRedeemed,
  couponInvalid,
  wrongPlan,
  belowMinimum,
  currencyMismatch,
  rejectedByStripe,
  unknown;

  /// Maps the server `reason` wire string to a typed value; an unrecognized or
  /// null string maps to [unknown] (never throws).
  static CheckoutPromoRejectionReason fromWire(String? wire) {
    switch (wire) {
      case 'not_found_or_inactive':
        return CheckoutPromoRejectionReason.notFoundOrInactive;
      case 'wrong_customer':
        return CheckoutPromoRejectionReason.wrongCustomer;
      case 'expired':
        return CheckoutPromoRejectionReason.expired;
      case 'max_redeemed':
        return CheckoutPromoRejectionReason.maxRedeemed;
      case 'coupon_invalid':
        return CheckoutPromoRejectionReason.couponInvalid;
      case 'wrong_plan':
        return CheckoutPromoRejectionReason.wrongPlan;
      case 'below_minimum':
        return CheckoutPromoRejectionReason.belowMinimum;
      case 'currency_mismatch':
        return CheckoutPromoRejectionReason.currencyMismatch;
      case 'rejected_by_stripe':
        return CheckoutPromoRejectionReason.rejectedByStripe;
      default:
        return CheckoutPromoRejectionReason.unknown;
    }
  }
}

/// Raised when `/subscription/checkout` rejects the REQUESTED promo code with
/// the business-rejection 422 shape
/// `{"detail": {"code": "promo_not_applicable", "reason": "<r>"}}`.
///
/// This is DISTINCT from a FastAPI schema-validation 422 (where `detail` is a
/// LIST of `extra_forbidden`/length errors) — that is a client bug and is
/// surfaced as a [CheckoutException] instead. Carries the typed [reason] so the
/// UI can show a specific message; [rawReason] preserves the exact wire string
/// for logging / forward-compat.
class PromoNotApplicableException implements Exception {
  final CheckoutPromoRejectionReason reason;
  final String? rawReason;

  const PromoNotApplicableException(this.reason, {this.rawReason});

  @override
  String toString() =>
      "PromoNotApplicableException: ${rawReason ?? reason.name}";
}

/// POSTs `/subscription/checkout` and resolves the Stripe Checkout session,
/// running the bounded "creating" poll (I3) and carrying the optional discount
/// code.
///
/// - Body is EXACTLY `{"planId": planId}` or `{"planId": planId, "promoCode":
///   promoCode}` sent with `injectUserContext: false` (I1) — the choreo
///   `CheckoutRequest` is `extra="forbid"`, so any injected/extra field is a
///   schema 422 (money-safety). The promo **code string** is the only discount
///   input; the client never sends amounts or coupon ids.
/// - Returns the resolved [CheckoutResponse]: `.sessionUrl` (the redirect
///   target) plus `.appliedPromoCode` — the code ACTUALLY on the session. On a
///   `reused` open session the request's `promoCode` is IGNORED server-side, so
///   `appliedPromoCode` (not the requested code) is the truth the UI reflects.
/// - On a `creating` (202) response, re-POSTs the SAME body after
///   `retryAfterSeconds` (fallback 2s), capped at 5 attempts / ~15s of waiting;
///   on exhaustion it throws a [CheckoutException].
/// - An invalid/inapplicable requested promo -> 422 `promo_not_applicable` ->
///   [PromoNotApplicableException] (typed [CheckoutPromoRejectionReason]). A
///   schema-shaped 422 (extra field / >64-char code) -> [CheckoutException]
///   (a client bug — a different promo code will not fix it).
/// - The delay is injected ([delay]) so tests run without real waits.
class CheckoutV2Repo {
  static const int maxAttempts = 5;
  static const Duration fallbackDelay = Duration(seconds: 2);
  static const Duration maxTotalWait = Duration(seconds: 15);

  static Future<CheckoutResponse> checkout(
    String planId, {
    String? promoCode,
    http.Client? client,
    Future<void> Function(Duration)? delay,
  }) {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
      client: client,
    );
    return checkoutWith(req, planId, promoCode: promoCode, delay: delay);
  }

  /// Pollable core, decoupled from `MatrixState` so the bounded-poll and
  /// promo-rejection behavior is unit-testable with an injected [Requests]
  /// (MockClient) + [delay] seam. Production callers use [checkout]; this is the
  /// same logic with the request transport supplied by the caller.
  static Future<CheckoutResponse> checkoutWith(
    Requests req,
    String planId, {
    String? promoCode,
    String? url,
    Future<void> Function(Duration)? delay,
  }) async {
    // Resolve lazily: only fall back to the Environment-backed URL when the
    // caller did not supply one, so unit tests can pass a literal URL and avoid
    // touching `Environment` (GetStorage/dotenv are not initialized under
    // `flutter test` — see endpoint_test_env.dart).
    final String target = url ?? PApiUrls.subscriptionCheckout;
    final Future<void> Function(Duration) delayFn =
        delay ?? (d) => Future<void>.delayed(d);

    // EXACTLY {planId[, promoCode]} — extra="forbid". Trim first, then omit
    // promoCode entirely when blank (an empty OR whitespace-only code must
    // never reach the server — it would 422 as not_found_or_inactive).
    final String? normalizedPromoCode = promoCode?.trim();
    final Map<String, dynamic> body = {
      "planId": planId,
      if (normalizedPromoCode != null && normalizedPromoCode.isNotEmpty)
        "promoCode": normalizedPromoCode,
    };

    var accumulatedWait = Duration.zero;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final http.Response res;
      try {
        res = await req.post(url: target, body: body, injectUserContext: false);
      } on http.Response catch (errRes) {
        // `Requests.handleError` throws the raw response for a non-string
        // `detail` — the two 422 shapes. Map them to typed outcomes. (A
        // string-detail error — 401/404/409/502/503 — surfaces as the usual
        // `ChoreoException` and is not caught here.)
        _throwForErrorResponse(errRes);
      }

      final parsed = CheckoutResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );

      if (parsed.isResolved) {
        final sessionUrl = parsed.sessionUrl;
        if (sessionUrl == null || sessionUrl.isEmpty) {
          throw CheckoutException(
            'Checkout resolved as "${parsed.status}" but returned no sessionUrl',
          );
        }
        return parsed;
      }

      if (!parsed.isCreating) {
        throw CheckoutException(
          'Unexpected checkout status "${parsed.status}"',
        );
      }

      // "creating": decide whether to poll again. Stop on the last attempt or
      // when the cumulative wait would exceed the total budget (I3).
      final Duration wait = parsed.retryAfterSeconds != null
          ? Duration(seconds: parsed.retryAfterSeconds!)
          : fallbackDelay;
      final bool isLastAttempt = attempt >= maxAttempts;
      final bool wouldExceedBudget = accumulatedWait + wait > maxTotalWait;
      if (isLastAttempt || wouldExceedBudget) break;

      accumulatedWait += wait;
      await delayFn(wait);
    }

    throw const CheckoutException(
      "Checkout session is still being created; please try again",
    );
  }

  /// Maps a thrown error [http.Response] (raised by `Requests.handleError` for a
  /// non-string `detail`) to a typed checkout failure. Never returns normally.
  static Never _throwForErrorResponse(http.Response res) {
    if (res.statusCode == 422) {
      Object? detail;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          detail = decoded['detail'];
        }
      } catch (_) {
        // Non-JSON body — fall through to the generic schema error.
      }

      // Business rejection: detail is an OBJECT {code, reason}.
      if (detail is Map && detail['code'] == 'promo_not_applicable') {
        final rawReason = detail['reason'] as String?;
        throw PromoNotApplicableException(
          CheckoutPromoRejectionReason.fromWire(rawReason),
          rawReason: rawReason,
        );
      }

      // Schema rejection: detail is a LIST (extra_forbidden / too-long code) —
      // a client bug (an unexpected body field or an over-length code). The UI
      // cannot fix it with a different promo code, so surface it as an error.
      throw CheckoutException(
        "Checkout request rejected by schema validation (HTTP 422): ${res.body}",
      );
    }

    // Any other non-string-detail failure — rethrow the raw response so the
    // caller's generic error handling takes over (mirrors prior behavior).
    throw res;
  }
}
