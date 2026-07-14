import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/utils/subscription_duration_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';

// Exercises the REAL SubscriptionController.submitSubscriptionChange (not just
// the SingleFlightGuard primitive) via the managerOverride seam + an L10n
// BuildContext. GoogleAnalytics.logEvent is a no-op under `flutter test`
// (analytics is null), so the non-trial buy path reaches the injected manager
// without RevenueCat/MatrixState.
class _FakeManager implements SubscriptionInfoManager {
  int submitCalls = 0;
  Completer<void>? block;
  Object? throwError;

  @override
  Future<SubscriptionState> getCurrentSubscriptionInfo({String? stripeAppId}) async =>
      SubscriptionInactive();

  @override
  Future<void> submitSubscriptionChange(SubscriptionDetails subscription) async {
    submitCalls++;
    if (block != null) await block!.future;
    if (throwError != null) throw throwError!;
  }
}

// A non-trial plan so submit takes the analytics + manager path (not the
// MatrixState-bound trial branch).
final _monthly = SubscriptionDetails(
  id: "month",
  price: 9.99,
  currency: "usd",
  appId: "stripe",
  duration: SubscriptionDuration.month,
);

void main() {
  testWidgets(
    'a concurrent second submit while one is in-flight is a NO-OP '
    '(manager invoked once; isSubmitting stays true until release)',
    (tester) async {
      final manager = _FakeManager()..block = Completer<void>();
      final controller = SubscriptionController(managerOverride: manager);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) {
              // First submit enters the guard and blocks inside the manager.
              final first = controller.submitSubscriptionChange(_monthly, context);
              // Second submit, while the first is in flight, must no-op.
              final second =
                  controller.submitSubscriptionChange(_monthly, context);

              scheduleMicrotask(() async {
                await second; // returns immediately (guard rejected)
                expect(manager.submitCalls, 1); // never reached the manager
                expect(controller.isSubmitting, isTrue); // first still in flight

                manager.block!.complete();
                await first;
                expect(manager.submitCalls, 1);
                expect(controller.isSubmitting, isFalse); // released
              });
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(manager.submitCalls, 1);
      expect(controller.isSubmitting, isFalse);
    },
  );

  testWidgets('the guard RELEASES on success — a later submit proceeds', (
    tester,
  ) async {
    final manager = _FakeManager();
    final controller = SubscriptionController(managerOverride: manager);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            scheduleMicrotask(() async {
              expect(controller.isSubmitting, isFalse);
              await controller.submitSubscriptionChange(_monthly, context);
              expect(manager.submitCalls, 1);
              expect(controller.isSubmitting, isFalse);

              // A later call proceeds (the guard was released).
              await controller.submitSubscriptionChange(_monthly, context);
              expect(manager.submitCalls, 2);
            });
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(manager.submitCalls, 2);
  });

  testWidgets('the guard RELEASES on throw — exit() is in finally', (
    tester,
  ) async {
    final manager = _FakeManager()..throwError = Exception("boom");
    final controller = SubscriptionController(managerOverride: manager);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            scheduleMicrotask(() async {
              await expectLater(
                controller.submitSubscriptionChange(_monthly, context),
                throwsA(isA<Exception>()),
              );
              expect(controller.isSubmitting, isFalse); // released despite throw

              // A subsequent submit still proceeds.
              manager.throwError = null;
              await controller.submitSubscriptionChange(_monthly, context);
              expect(manager.submitCalls, 2);
            });
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(manager.submitCalls, 2);
    expect(controller.isSubmitting, isFalse);
  });
}
