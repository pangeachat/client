import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_provider.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

typedef ValidationLoader = ValueNotifier<AsyncState<ValidatePromoCodeResponse>>;

class DiscountCodeViewModel {
  final String _userID;
  DiscountCodeViewModel({required String userID}) : _userID = userID {
    _productsProvider.load(ProductsRequest(userID: _userID));
  }

  final TextEditingController _controller = TextEditingController();
  final ValidationLoader _loader = ValidationLoader(AsyncIdle());
  final ValueNotifier<ProductPlan?> _selectedSubscription = ValueNotifier(null);
  final ProductsProvider _productsProvider = ProductsProvider();

  int _generation = 0;
  bool _disposed = false;

  TextEditingController get controller => _controller;
  ValidationLoader get loader => _loader;
  ValueNotifier<ProductPlan?> get selectedSubscription => _selectedSubscription;

  ValueNotifier<AsyncState<List<ProductPlan>>> get productsNotifier =>
      _productsProvider.loader;

  String title(L10n l10n) => switch (_loader.value) {
    AsyncLoaded(value: final response) =>
      response.valid == true ? l10n.selectDiscountPlan : l10n.enterDiscountCode,
    _ => l10n.enterDiscountCode,
  };

  void dispose() {
    _disposed = true;
    _controller.dispose();
    _loader.dispose();
    _selectedSubscription.dispose();
    _productsProvider.dispose();
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

    final result = await ValidatePromoCodeRepo.instance.get(
      ValidatePromoCodeRequest(userID: _userID, code: _controller.text.trim()),
    );
    final response = result.result;
    _setLoaderValue(
      generation,
      response != null
          ? AsyncLoaded(response)
          : AsyncError(result.error ?? "Failed to validate promo code"),
    );
  }
}
