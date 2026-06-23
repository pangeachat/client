import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_response.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';

/// Version-pin fallback threading: the choreo fetch's `used_fallback_version` /
/// `fallback_cause` must reach the call sites that emit the `version_pin_honored`
/// analytics dimension, via the response → mapper → model path (and survive the
/// session-event round-trip read by completeActivity).
void main() {
  Map<String, dynamic> rawPlan() => {
    'activity_id': 'a1',
    'title': 'Cafe',
    'description': 'Order coffee.',
    'learning_objective': 'Greet politely.',
    'roles': [
      {'role_id': 'r1', 'name': 'Customer'},
    ],
  };

  group('version-pin fallback threading', () {
    test(
      'fetch response parses fallback fields and carries them to the model',
      () {
        final resp = ActivityPlanFetchResponse.fromJson({
          'plan': rawPlan(),
          'l1': 'fr',
          'version_id': 'v1',
          'used_fallback_version': true,
          'fallback_cause': 'version_evicted',
        });
        expect(resp.usedFallbackVersion, isTrue);
        expect(resp.fallbackCause, 'version_evicted');

        final plan = resp.plan;
        expect(plan.usedFallbackVersion, isTrue);
        expect(plan.fallbackCause, 'version_evicted');
        // version_pin_honored is derived as !usedFallbackVersion at the call site.
        expect(!plan.usedFallbackVersion, isFalse);
      },
    );

    test('clean pin hit defaults to honored with no cause', () {
      final resp = ActivityPlanFetchResponse.fromJson({
        'plan': rawPlan(),
        'version_id': 'v1',
      });
      expect(resp.usedFallbackVersion, isFalse);
      expect(resp.fallbackCause, isNull);
      expect(resp.plan.usedFallbackVersion, isFalse);
      expect(resp.plan.fallbackCause, isNull);
    });

    test('fields survive withMedia and the session-event round-trip', () {
      final plan = ActivityPlanFetchResponse.fromJson({
        'plan': rawPlan(),
        'used_fallback_version': true,
        'fallback_cause': 'cms_unavailable',
      }).plan;

      // withMedia must not drop the fields (it rebuilds the model).
      expect(plan.withMedia(const []).usedFallbackVersion, isTrue);
      expect(plan.withMedia(const []).fallbackCause, 'cms_unavailable');

      // completeActivity reads room.activityPlan, which for embedded sessions
      // comes back through fromJson(toJson) — the fields must persist.
      final restored = ActivityPlanModel.fromJson(plan.toJson());
      expect(restored.usedFallbackVersion, isTrue);
      expect(restored.fallbackCause, 'cms_unavailable');
    });
  });
}
