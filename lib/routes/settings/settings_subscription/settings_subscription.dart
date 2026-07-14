import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription_view.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

typedef _StatusLoader = ValueNotifier<AsyncState<SubscriptionStatusResponse>>;

class SettingsSubscription extends StatefulWidget {
  final Widget closeButton;
  const SettingsSubscription({super.key, required this.closeButton});

  @override
  SettingsSubscriptionState createState() => SettingsSubscriptionState();
}

class SettingsSubscriptionState extends State<SettingsSubscription> {
  final _loader = _StatusLoader(AsyncLoading());

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
    final result = await SubscriptionStatusRepo.instance.get(
      SubscriptionStatusRequest(userID: Matrix.of(context).client.userID!),
    );
    final response = result.result;
    if (mounted) {
      _loader.value = response != null
          ? AsyncLoaded(response)
          : AsyncError(result.error ?? "Failed to fetch subscription status");
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
        AsyncLoaded(value: final status) => SettingsSubscriptionView(
          closeButton: widget.closeButton,
          subscriptionStatus: status,
        ),
      },
    );
  }
}
