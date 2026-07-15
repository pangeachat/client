import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_status_provider.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionStatusBuilder extends StatefulWidget {
  final Widget Function(BuildContext, AsyncState<SubscriptionStatusResponse>)
  builder;
  const SubscriptionStatusBuilder({super.key, required this.builder});

  @override
  SubscriptionStatusBuilderState createState() =>
      SubscriptionStatusBuilderState();
}

class SubscriptionStatusBuilderState extends State<SubscriptionStatusBuilder> {
  final _provider = SubscriptionStatusProvider();

  @override
  void initState() {
    super.initState();
    _provider.load(
      SubscriptionStatusRequest(userID: Matrix.of(context).client.userID!),
    );
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
