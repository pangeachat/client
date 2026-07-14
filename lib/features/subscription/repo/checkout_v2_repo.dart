import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/subscription/models/checkout_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Raised when a `/subscription/checkout` flow cannot be resolved to a session
/// URL — a malformed terminal response, an unexpected status, or the bounded
/// poll giving up. User-visible (I3).
class CheckoutException implements Exception {
  final String message;
  const CheckoutException(this.message);

  @override
  String toString() => "CheckoutException: $message";
}

/// POSTs `/subscription/checkout` and resolves the Stripe Checkout session URL,
/// running the bounded "creating" poll (I3).
///
/// - Body is EXACTLY `{"planId": planId}` sent with `injectUserContext: false`
///   (I1) — the choreo `CheckoutRequest` is `extra="forbid"`, so any injected
///   field is a 422 (money-safety).
/// - On a `creating` (202) response, re-POSTs the SAME body after
///   `retryAfterSeconds` (fallback 2s), capped at 5 attempts / ~15s of waiting;
///   on exhaustion it throws a [CheckoutException].
/// - The delay is injected ([delay]) so tests run without real waits.
class CheckoutV2Repo {
  static const int maxAttempts = 5;
  static const Duration fallbackDelay = Duration(seconds: 2);
  static const Duration maxTotalWait = Duration(seconds: 15);

  static Future<String> checkout(
    String planId, {
    http.Client? client,
    Future<void> Function(Duration)? delay,
  }) {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
      client: client,
    );
    return checkoutWith(req, planId, delay: delay);
  }

  /// Pollable core, decoupled from `MatrixState` so the bounded-poll behavior
  /// is unit-testable with an injected [Requests] (MockClient) + [delay] seam.
  /// Production callers use [checkout]; this is the same logic with the request
  /// transport supplied by the caller.
  static Future<String> checkoutWith(
    Requests req,
    String planId, {
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

    var accumulatedWait = Duration.zero;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final http.Response res = await req.post(
        url: target,
        body: {"planId": planId},
        injectUserContext: false,
      );
      final parsed = CheckoutResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );

      if (parsed.isResolved) {
        final url = parsed.sessionUrl;
        if (url == null || url.isEmpty) {
          throw CheckoutException(
            'Checkout resolved as "${parsed.status}" but returned no sessionUrl',
          );
        }
        return url;
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
}
