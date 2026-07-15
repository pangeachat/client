import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

typedef _ProductsLoader = ValueNotifier<AsyncState<List<ProductPlan>>>;

class ProductsBuilder extends StatefulWidget {
  final Widget Function(BuildContext, AsyncState<List<ProductPlan>>) builder;
  const ProductsBuilder({super.key, required this.builder});

  @override
  ProductsBuilderState createState() => ProductsBuilderState();
}

class ProductsBuilderState extends State<ProductsBuilder> {
  final _loader = _ProductsLoader(AsyncLoading());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ProductsRepo.instance.get(
      ProductsRequest(userID: Matrix.of(context).client.userID!),
    );
    final response = result.result;
    if (mounted) {
      _loader.value = response != null
          ? AsyncLoaded(response.plans)
          : AsyncError(result.error ?? "Failed to fetch products");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _loader,
      builder: (context, state, _) => widget.builder(context, state),
    );
  }
}
