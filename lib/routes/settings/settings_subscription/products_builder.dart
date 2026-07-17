import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_provider.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ProductsBuilder extends StatefulWidget {
  final Widget Function(BuildContext, AsyncState<List<ProductPlan>>) builder;
  const ProductsBuilder({super.key, required this.builder});

  @override
  ProductsBuilderState createState() => ProductsBuilderState();
}

class ProductsBuilderState extends State<ProductsBuilder> {
  final _provider = ProductsProvider();

  @override
  void initState() {
    super.initState();
    _provider.load(ProductsRequest(userID: Matrix.of(context).client.userID!));
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _provider.loader,
      builder: (context, state, _) => widget.builder(context, state),
    );
  }
}
