import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/billing_portal_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/billing_portal_response.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';

class BillingPortalRepo
    extends BaseRepo<BillingPortalRequest, BillingPortalResponse> {
  BillingPortalRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: BillingPortalResponse.fromJson,
        cacheDuration: Duration(minutes: 10),
        timeout: Duration(seconds: 10),
      );

  static final BillingPortalRepo _instance = BillingPortalRepo._internal();
  static BillingPortalRepo get instance => _instance;

  /// The choreographer's answer for a user with no canonical Stripe customer
  /// row — comped, seat-sponsored, or simply never purchased.
  static const int noBillingAccountStatus = 404;

  @override
  Future<Response> fetch(Requests req, BillingPortalRequest _) async {
    try {
      return await req.get(url: PApiUrls.billingPortal);
    } catch (e) {
      final noBillingAccount = noBillingAccountResponse(e);
      if (noBillingAccount == null) rethrow;
      return noBillingAccount;
    }
  }

  /// The successful empty response for [error] when it is the expected
  /// no-billing-account state, else null so [BaseRepo] reports and returns it
  /// as the failure it is.
  ///
  /// A 404 here means "this user has no billing account", which is a normal
  /// state rather than something the user can act on — the severity table
  /// already reads 404 as "the resource is gone", and repos
  /// "never return an error the user cannot be told about"
  /// (repos-and-error-handling.instructions.md). Mapped inside [fetch] so
  /// [BaseRepo] never sees an exception and never opens a Sentry issue for it
  /// (#8374 / CLIENT-E43).
  @visibleForTesting
  static Response? noBillingAccountResponse(Object error) =>
      PangeaHttpException.statusCodeOf(error) == noBillingAccountStatus
      ? Response(
          jsonEncode(BillingPortalResponse.noBillingAccount().toJson()),
          200,
        )
      : null;

  /// Never memoize the empty value: it flips the moment the user completes
  /// checkout, and pinning it for the full [cacheDuration] would leave a
  /// just-subscribed user unable to reach their billing portal.
  @override
  bool shouldCache(BillingPortalResponse response) =>
      response.hasBillingAccount;
}
