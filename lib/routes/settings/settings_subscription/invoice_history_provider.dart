import 'package:async/async.dart';

import 'package:fluffychat/features/subscription/repo_v2/invoice_history_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_response.dart';
import 'package:fluffychat/pangea/common/utils/async_repo_loader.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class InvoiceHistoryProvider
    extends AsyncRepoLoader<InvoiceHistoryRequest, List<Invoice>> {
  @override
  Future<Result<List<Invoice>>> get(InvoiceHistoryRequest request) async {
    final result = await InvoiceHistoryRepo.instance.get(request);
    final response = result.result;
    if (response == null) {
      return Result.error(result.error ?? "Failed to fetch invoice history");
    }
    return Result.value(response.invoices);
  }
}
