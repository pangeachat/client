import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

typedef StatusLoader = ValueNotifier<AsyncState<SubscriptionStatusResponse>>;

class SubscriptionStatusProvider {
  final _loader = StatusLoader(AsyncLoading());
  bool _disposed = false;

  StatusLoader get loader => _loader;

  void dispose() {
    _disposed = true;
    _loader.dispose();
  }

  Future<void> load(SubscriptionStatusRequest request) async {
    final result = await SubscriptionStatusRepo.instance.get(request);
    final response = result.result;
    if (!_disposed) {
      _loader.value = response != null
          ? AsyncLoaded(response)
          : AsyncError(result.error ?? "Failed to fetch subscription status");
    }
  }
}
