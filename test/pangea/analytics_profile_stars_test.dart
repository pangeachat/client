import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The published star total is a high-water mark (#8438): every way the local
/// count can be wrong makes it too LOW — a device part-way through its first
/// sync is missing rooms, and a session's language only arrives once its
/// activity plan has been fetched — so a smaller number never wins. See
/// profile.instructions.md.
void main() {
  AnalyticsProfileModel withStars(String langCode, int stars) {
    final profile = AnalyticsProfileModel();
    profile.raiseStars(langCode, stars);
    return profile;
  }

  group('raiseStars', () {
    test('sets the total for a language it has never held', () {
      final profile = AnalyticsProfileModel();
      expect(profile.raiseStars('fr', 7), isTrue);
      expect(profile.starsByLanguage('fr'), 7);
    });

    test('raises a lower total', () {
      final profile = withStars('fr', 7);
      expect(profile.raiseStars('fr', 12), isTrue);
      expect(profile.starsByLanguage('fr'), 12);
    });

    test('a lower count is ignored — a device behind never lowers it', () {
      final profile = withStars('fr', 12);
      expect(profile.raiseStars('fr', 3), isFalse);
      expect(profile.starsByLanguage('fr'), 12);
    });

    test('an equal count reports no change, so nothing is published', () {
      expect(withStars('fr', 12).raiseStars('fr', 12), isFalse);
    });

    test('a count of zero never clears a published total', () {
      final profile = withStars('fr', 12);
      expect(profile.raiseStars('fr', 0), isFalse);
      expect(profile.starsByLanguage('fr'), 12);
    });

    test('a regional variant counts as its language', () {
      final profile = withStars('fr', 12);
      expect(profile.raiseStars('fr-CA', 15), isTrue);
      expect(profile.starsByLanguage('fr'), 15);
    });

    test('languages are independent', () {
      final profile = withStars('fr', 12);
      profile.raiseStars('de', 2);
      expect(profile.starsByLanguage('fr'), 12);
      expect(profile.starsByLanguage('de'), 2);
    });

    test('leaves the level alone', () {
      final profile = AnalyticsProfileModel();
      profile.setLanguageInfo('fr', 4, null);
      profile.raiseStars('fr', 9);
      expect(profile.levelByLanguage('fr'), 4);
      expect(profile.starsByLanguage('fr'), 9);
    });
  });

  group('serialization', () {
    test('a published total survives a round trip', () {
      final parsed = AnalyticsProfileModel.fromJson({
        PangeaEventTypes.profileAnalytics: withStars('fr', 12).toJson(),
      });
      expect(parsed.starsByLanguage('fr'), 12);
    });

    test('a profile written before stars existed reads as zero, not null', () {
      final parsed = AnalyticsProfileModel.fromJson({
        PangeaEventTypes.profileAnalytics: {
          AnalyticsConstants.analytics: {
            'fr': {AnalyticsConstants.level: 3},
          },
        },
      });
      expect(parsed.starsByLanguage('fr'), 0);
      expect(parsed.levelByLanguage('fr'), 3);
    });

    test('legacy per-variant keys collapse to the largest total', () {
      final parsed = AnalyticsProfileModel.fromJson({
        PangeaEventTypes.profileAnalytics: {
          AnalyticsConstants.analytics: {
            'fr': {AnalyticsConstants.stars: 4},
            'fr-CA': {AnalyticsConstants.stars: 11},
          },
        },
      });
      expect(parsed.starsByLanguage('fr'), 11);
    });
  });
}
