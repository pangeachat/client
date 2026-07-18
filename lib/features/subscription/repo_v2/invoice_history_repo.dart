import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/invoice_history_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';

class InvoiceHistoryRepo
    extends BaseRepo<InvoiceHistoryRequest, InvoiceHistoryResponse> {
  InvoiceHistoryRepo._internal()
    : super(
        cache: PersistentRepoCache('subscription_history_storage'),
        responseFromJson: InvoiceHistoryResponse.fromJson,
        cacheDuration: const Duration(minutes: 10),
        timeout: Duration(seconds: 10),
      );

  static final InvoiceHistoryRepo _instance = InvoiceHistoryRepo._internal();
  static InvoiceHistoryRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, InvoiceHistoryRequest _) =>
      req.get(url: PApiUrls.subscriptionHistory);
}
