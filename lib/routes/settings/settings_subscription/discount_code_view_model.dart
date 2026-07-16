import 'package:flutter/material.dart';

import 'package:async/async.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

typedef ValidationLoader = ValueNotifier<AsyncState<ValidatePromoCodeResponse>>;

class DiscountCodeViewModel {
  final Future<Result<ValidatePromoCodeResponse>> Function(String) validateCode;
  DiscountCodeViewModel({required this.validateCode});

  final TextEditingController _controller = TextEditingController();
  final ValidationLoader _loader = ValidationLoader(AsyncIdle());
  final ValueNotifier<ProductPlan?> _selectedSubscription = ValueNotifier(null);

  int _generation = 0;
  bool _disposed = false;

  TextEditingController get controller => _controller;
  ValidationLoader get loader => _loader;
  ValueNotifier<ProductPlan?> get selectedSubscription => _selectedSubscription;

  String title(L10n l10n) => switch (_loader.value) {
    AsyncLoaded() => l10n.selectDiscountPlan,
    _ => l10n.enterDiscountCode,
  };

  void dispose() {
    _disposed = true;
    _controller.dispose();
    _loader.dispose();
    _selectedSubscription.dispose();
  }

  void setSelectedSubscription(ProductPlan plan) =>
      _selectedSubscription.value = plan;

  void _setLoaderValue(
    int generation,
    AsyncState<ValidatePromoCodeResponse> value,
  ) {
    if (!_disposed && _generation == generation) {
      _loader.value = value;
    }
  }

  Future<void> validatePromoCode() async {
    _generation++;
    final generation = _generation;
    _setLoaderValue(generation, AsyncLoading());

    final result = await validateCode(_controller.text.trim());
    final response = result.result;
    _setLoaderValue(
      generation,
      response != null
          ? AsyncLoaded(response)
          : AsyncError(result.error ?? "Failed to validate promo code"),
    );
  }
}
