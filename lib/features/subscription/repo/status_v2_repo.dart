import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fluffychat/features/subscription/models/subscription_status_v2.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Fetches the Subscriptions-v2 `/subscription/status` response and parses it
/// into [SubscriptionStatusV2]. Throws on a network/parse failure so the caller
/// (the web manager) can surface a `SubscriptionError`, mirroring the RC
/// `SubscriptionRepo.getCurrentSubscriptionInfo` contract. NEVER runs the RC
/// parser on this payload (I7).
class StatusV2Repo {
  static Future<SubscriptionStatusV2> get({http.Client? client}) async {
    final Requests req = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
      client: client,
    );
    final http.Response res = await req.get(url: PApiUrls.subscriptionStatus);
    final Map<String, dynamic> json =
        jsonDecode(res.body) as Map<String, dynamic>;
    return SubscriptionStatusV2.fromJson(json);
  }
}
