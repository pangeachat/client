import 'package:flutter/material.dart';

import 'package:async/async.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

abstract class AsyncRepoLoader<TRequest extends BaseRequest, TResponse> {
  final ValueNotifier<AsyncState<TResponse>> _loader = ValueNotifier(
    AsyncIdle(),
  );
  bool _disposed = false;

  ValueNotifier<AsyncState<TResponse>> get loader => _loader;

  TResponse? get response => switch (_loader.value) {
    AsyncLoaded(value: final response) => response,
    _ => null,
  };

  void dispose() {
    _disposed = true;
    _loader.dispose();
  }

  Future<Result<TResponse>> get(TRequest request);

  Future<void> load(TRequest request) async {
    final result = await get(request);
    final response = result.result;
    if (!_disposed) {
      _loader.value = response != null
          ? AsyncLoaded(response)
          : AsyncError(result.error ?? "Failed to fetch");
    }
  }
}
