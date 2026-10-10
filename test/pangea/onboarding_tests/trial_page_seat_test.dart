import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';

/// A student who already holds a seat is not offered the free trial during
/// onboarding ("7 DAYS FREE / Claim your trial"): the seat is their access.
/// The decision reads the subscription status the app already loaded.
void main() {
  sqfliteFfiInit();

  Map<String, dynamic> status(List<Map<String, dynamic>> entitlements) => {
    'access_level': 'full',
    'entitlements': entitlements,
    'trial_eligible': true,
    'trial_claimed': false,
  };

  Map<String, dynamic> entitlement(String type, {String state = 'active'}) => {
    'entitlementRef': '$type:1',
    'type': type,
    'status': state,
    'ends_at': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
  };

  group('SubscriptionStatusResponse.hasActiveSeat', () {
    test('an active seat counts', () {
      expect(
        SubscriptionStatusResponse.fromJson(
          status([entitlement('seat')]),
        ).hasActiveSeat,
        isTrue,
      );
    });

    test('no seat, an ended seat, or another kind of access does not', () {
      for (final entitlements in [
        <Map<String, dynamic>>[],
        [entitlement('seat', state: 'canceled')],
        [entitlement('trial')],
        [entitlement('paid')],
      ]) {
        expect(
          SubscriptionStatusResponse.fromJson(
            status(entitlements),
          ).hasActiveSeat,
          isFalse,
          reason: '$entitlements',
        );
      }
    });
  });

  group('ClientTrialInfoProvider.shouldShowTrialPage', () {
    late matrix.Client client;

    setUp(() async {
      client = matrix.Client(
        'trial-page-seat',
        database: await matrix.MatrixSdkDatabase.init(
          'trial-page-seat',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
    });

    test('a seat holder skips the trial page', () {
      expect(
        ClientTrialInfoProvider(
          client: client,
          inTrialWindow: true,
          hasSeat: () => true,
        ).shouldShowTrialPage,
        isFalse,
      );
    });

    test('without a seat the trial page shows as before', () {
      expect(
        ClientTrialInfoProvider(
          client: client,
          inTrialWindow: true,
          hasSeat: () => false,
        ).shouldShowTrialPage,
        isTrue,
      );
    });

    test('the seat is read when the step is decided, not when onboarding '
        'starts (the status may still be loading then)', () {
      var seat = false;
      final provider = ClientTrialInfoProvider(
        client: client,
        inTrialWindow: true,
        hasSeat: () => seat,
      );
      expect(provider.shouldShowTrialPage, isTrue);
      seat = true;
      expect(provider.shouldShowTrialPage, isFalse);
    });
  });
}
