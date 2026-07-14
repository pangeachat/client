import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/subscription/models/cancel_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// POSTs `/subscription/cancel` to set the user-owned subscription to cancel at
/// period end.
///
/// Body is EXACTLY `{"entitlementRef": ref}` sent with
/// `injectUserContext: false` (I1) — the server resolves the OWNED entitlement
/// from `(authenticated user, entitlementRef)`, so a client can never cancel a
/// subscription it does not own, and the ref is NEVER a Stripe id (I5).
class CancelV2Repo {
  static Future<CancelResponse> cancel(
    String entitlementRef, {
    http.Client? client,
  }) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
      client: client,
    );
    final http.Response res = await req.post(
      url: PApiUrls.subscriptionCancel,
      body: {"entitlementRef": entitlementRef},
      injectUserContext: false,
    );
    return CancelResponse.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }
}
