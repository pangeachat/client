import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_model.dart';

/// Covers #9226 (CLIENT-ETQ): a blank discount code must never reach
/// `validate_promo_code`, which forwards it to Stripe as an empty `code`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The constructor loads the plan list, whose cache is a GetStorage box.
    final tempDir = await Directory.systemTemp.createTemp('discount_code_vm');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
  });

  group('DiscountCodeViewModel blank code', () {
    late DiscountCodeViewModel viewModel;

    // The constructor's plan-list load needs a signed-in MatrixState, which
    // this test has none of; that load is not under test, so its failure is
    // contained here instead of failing the test after it completes.
    setUp(
      () => runZonedGuarded(
        () => viewModel = DiscountCodeViewModel(userID: '@u:test'),
        (_, _) {},
      ),
    );
    tearDown(() => viewModel.dispose());

    for (final text in ['', '   ']) {
      test('"$text" cannot be validated and sends nothing', () async {
        viewModel.controller.text = text;
        expect(viewModel.canValidate, isFalse);

        await viewModel.validatePromoCode();
        expect(viewModel.loader.value, isA<AsyncIdle>());
      });
    }

    test('a non-blank code can be validated', () {
      viewModel.controller.text = ' SAVE10 ';
      expect(viewModel.canValidate, isTrue);
    });
  });

  group('DiscountCodeViewModel link code (subscriptions § Gift link)', () {
    test('a gift link\'s code is filled in and validated at once', () async {
      late DiscountCodeViewModel viewModel;
      // Drives the real repo singleton, as the other repo tests do. With no
      // signed-in MatrixState its `createRequests` throws before any request
      // is built, so the validation fails deterministically and off the
      // network; that specific failure is asserted below, so a hang or a
      // pre-validation failure cannot pass. The zone guard contains only the
      // constructor's unrelated plan-list load (see setUp above).
      runZonedGuarded(
        () => viewModel = DiscountCodeViewModel(
          userID: '@u:test',
          initialCode: 'TESOL26-alice2026',
        ),
        (_, _) {},
      );
      expect(viewModel.controller.text, 'TESOL26-alice2026');
      // Started synchronously, before any tap: never idle.
      expect(viewModel.loader.value, isA<AsyncLoading>());

      await pumpEventQueue();
      final settled = viewModel.loader.value;
      expect(settled, isA<AsyncError>());
      final error = (settled as AsyncError).error;
      expect(error.toString(), contains('pangeaController'));
      viewModel.dispose();
    });
  });
}
