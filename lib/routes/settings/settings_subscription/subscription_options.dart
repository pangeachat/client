import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

typedef _ProductsLoader = ValueNotifier<AsyncState<List<ProductPlan>>>;

class SubscriptionOptions extends StatefulWidget {
  const SubscriptionOptions({super.key});

  @override
  SubscriptionOptionsState createState() => SubscriptionOptionsState();
}

class SubscriptionOptionsState extends State<SubscriptionOptions> {
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
      builder: (context, state, _) => switch (state) {
        AsyncLoading() ||
        AsyncIdle() => Center(child: CircularProgressIndicator.adaptive()),
        AsyncError() => SizedBox.shrink(),
        AsyncLoaded(value: final plans) => SubscriptionOptionsInternal(plans),
      },
    );
  }
}

class SubscriptionOptionsInternal extends StatelessWidget {
  final List<ProductPlan> plans;
  const SubscriptionOptionsInternal(this.plans, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 12.0,
      children: [
        Text(L10n.of(context).selectYourPlan),
        Row(
          spacing: 12.0,
          children: plans
              .map((p) => Expanded(child: _SubscriptionOptionCard(p)))
              .toList(),
        ),
      ],
    );
  }
}

class _SubscriptionOptionCard extends StatelessWidget {
  final ProductPlan plan;
  const _SubscriptionOptionCard(this.plan);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return FrameContainer(
      title: plan.duration.cardTitle(l10n),
      frameColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onPrimary,
      padding: EdgeInsets.all(8.0),
      titlePadding: EdgeInsetsGeometry.symmetric(
        vertical: 8.0,
        horizontal: 2.0,
      ),
      borderRadius: 12.0,
      child: Column(
        spacing: 8.0,
        children: [Text(plan.duration.copy(l10n)), Text(plan.priceDisplay)],
      ),
    );
  }
}
