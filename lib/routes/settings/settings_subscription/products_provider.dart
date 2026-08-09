import 'package:async/async.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/pangea/common/utils/async_repo_loader.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ProductsProvider
    extends AsyncRepoLoader<ProductsRequest, List<ProductPlan>> {
  @override
  Future<Result<List<ProductPlan>>> get(ProductsRequest request) async {
    final result = await ProductsRepo.instance.get(request);
    final response = result.result;
    if (response == null) {
      return Result.error(
        result.error ?? "Failed to fetch subscription products",
      );
    }
    return Result.value(response.plans);
  }
}
