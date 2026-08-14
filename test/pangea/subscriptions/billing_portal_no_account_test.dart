import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/billing_portal_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/billing_portal_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/routes/settings/settings_subscription/user_subscription_plan_card.dart';

/// Covers #8374 (Sentry CLIENT-E43): the choreographer answers
/// `404 — No billing account` for a user with no canonical Stripe customer,
/// which `BillingPortalRepo` reported as a failure and handed back as
/// `Result.error`. Per repos-and-error-handling.instructions.md a 404 is "the
/// resource is gone — a normal state", and "repos never return an error the
/// user cannot be told about" — so this reads as a successful
/// no-billing-account value instead, and the settings page stops rendering a
/// permanently-dead "Change" button on top of it.
void main() {
  group('BillingPortalResponse — the no-billing-account value', () {
    test('a payload without a url parses as no billing account', () {
      final response = BillingPortalResponse.fromJson(const {});
      expect(response.url, isNull);
      expect(response.hasBillingAccount, isFalse);
    });

    test('a payload with a url parses as a usable portal', () {
      final response = BillingPortalResponse.fromJson(const {
        'url': 'https://billing.stripe.com/session',
      });
      expect(response.url, 'https://billing.stripe.com/session');
      expect(response.hasBillingAccount, isTrue);
    });

    test('the no-billing-account value round-trips through json', () {
      final round = BillingPortalResponse.fromJson(
        jsonDecode(
              jsonEncode(BillingPortalResponse.noBillingAccount().toJson()),
            )
            as Map<String, dynamic>,
      );
      expect(round.hasBillingAccount, isFalse);
    });
  });

  group(
    'BillingPortalRepo.noBillingAccountResponse — which failures are states',
    () {
      test('a 404 becomes a successful, empty portal response', () {
        final synthesized = BillingPortalRepo.noBillingAccountResponse(
          PangeaHttpException(
            statusCode: 404,
            method: 'GET',
            path: '/subscription/billing_portal',
            detail: 'No billing account',
          ),
        );

        expect(synthesized, isNotNull);
        expect(synthesized!.statusCode, 200);
        expect(
          BillingPortalResponse.fromJson(
            jsonDecode(synthesized.body) as Map<String, dynamic>,
          ).hasBillingAccount,
          isFalse,
        );
      });

      test('a 500 is left alone, so BaseRepo still reports it', () {
        expect(
          BillingPortalRepo.noBillingAccountResponse(
            PangeaHttpException(
              statusCode: 500,
              method: 'GET',
              path: '/subscription/billing_portal',
            ),
          ),
          isNull,
        );
      });

      test('a timeout is left alone, so BaseRepo still reports it', () {
        expect(
          BillingPortalRepo.noBillingAccountResponse(TimeoutException('slow')),
          isNull,
        );
      });
    },
  );

  group('BillingPortalRepo.shouldCache — the empty value is not pinned', () {
    test('a real portal url is cached', () {
      expect(
        BillingPortalRepo.instance.shouldCache(
          BillingPortalResponse(url: 'https://billing.stripe.com/session'),
        ),
        isTrue,
      );
    });

    test(
      'no-billing-account is not cached, so a new purchase is picked up',
      () {
        expect(
          BillingPortalRepo.instance.shouldCache(
            BillingPortalResponse.noBillingAccount(),
          ),
          isFalse,
        );
      },
    );
  });

  group('UserSubscriptionPlanCard — no dead "Change" control', () {
    Future<void> pump(WidgetTester tester, {required bool canManage}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppConfig.primaryColor,
            ),
          ),
          home: Scaffold(
            body: UserSubscriptionPlanCard(
              subscriptionTitle: 'Pangea Pro',
              // What the settings page now passes: the manage affordance is
              // offered only once a billing portal actually resolved.
              showManage: canManage,
              canManageNotifier: ValueNotifier(canManage),
              onManage: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a billing portal renders an enabled Change button', (
      tester,
    ) async {
      await pump(tester, canManage: true);

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Change'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('no billing account renders no Change button at all', (
      tester,
    ) async {
      await pump(tester, canManage: false);

      expect(find.text('Change'), findsNothing);
    });
  });
}
