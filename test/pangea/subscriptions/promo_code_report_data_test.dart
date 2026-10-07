import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_request.dart';

/// A promo code names one person's gift or discount, so a failed request
/// reports everything about itself except the code (#9281; the repo layer
/// attaches `toReportData` to the Sentry event, never the raw body).
void main() {
  const code = 'TESOL26-alice2026';

  test('a failed validation never reports the code', () {
    final request = ValidatePromoCodeRequest(userID: '@u:test', code: code);
    expect(request.toJson()['code'], code);
    expect(request.toReportData().values, isNot(contains(code)));
    expect(request.toReportData().keys, isNot(contains('code')));
  });

  test('a failed checkout reports that a code was sent, not which', () {
    final request = CheckoutRequest(
      userID: '@u:test',
      planId: 'plan_1',
      promoCode: code,
    );
    expect(request.toJson()['promoCode'], code);
    expect(request.toReportData(), {'planId': 'plan_1', 'hasPromoCode': true});
  });

  test('a request without a code reports its body as is', () {
    final request = CheckoutRequest(userID: '@u:test', planId: 'plan_1');
    expect(request.toReportData(), {'planId': 'plan_1', 'hasPromoCode': false});
  });
}
