import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The public analytics profile is a MIRROR of per-language analytics that
/// other users cannot read directly, and it is keyed per language, by short
/// code. #8582: keying it per locale gave `fr`, `fr-FR` and `fr-CA` three
/// independent entries over one shared XP total, each frozen at whatever the
/// level was the last time that exact locale was the active target language.
void main() {
  Map<String, dynamic> profileJson(Map<String, dynamic> analytics) => {
    PangeaEventTypes.profileAnalytics: {
      'target_language': 'fr',
      'source_language': 'en',
      'analytics': analytics,
    },
  };

  group('parsing', () {
    test('collapses legacy per-locale keys onto the language, highest level '
        'winning', () {
      final profile = AnalyticsProfileModel.fromJson(
        profileJson({
          'fr': {'level': 2, 'xp_offset': 0},
          'fr-FR': {'level': 5, 'xp_offset': 0},
          'fr-CA': {'level': 13, 'xp_offset': 4},
        }),
      );

      expect(profile.languageAnalytics!.keys, ['fr']);
      expect(profile.languageAnalytics!['fr']!.level, 13);
      expect(profile.languageAnalytics!['fr']!.xpOffset, 4);
    });

    test('keeps an analytics room id contributed by any variant', () {
      final profile = AnalyticsProfileModel.fromJson(
        profileJson({
          'es': {'level': 3, 'xp_offset': 0},
          'es-MX': {'level': 1, 'xp_offset': 0, 'analytics_room_id': '!a:x'},
        }),
      );

      expect(profile.languageAnalytics!['es']!.analyticsRoomId, '!a:x');
    });

    test('the exact language key wins the room id over a variant', () {
      // Deterministic regardless of the order the server returns the keys in:
      // iterating the decoded map directly made the winner depend on that.
      final profile = AnalyticsProfileModel.fromJson(
        profileJson({
          'fr-CA': {'level': 2, 'xp_offset': 0, 'analytics_room_id': '!ca:x'},
          'fr': {'level': 3, 'xp_offset': 0, 'analytics_room_id': '!fr:x'},
        }),
      );

      expect(profile.languageAnalytics!['fr']!.analyticsRoomId, '!fr:x');
    });

    test('the largest XP offset wins, so a protected level cannot drop', () {
      // Largest, not sum: the offset exists so a level never visibly drops, and
      // the largest any variant recorded is the highest level this learner was
      // ever protected at. Summing would publish one higher than they ever saw.
      final profile = AnalyticsProfileModel.fromJson(
        profileJson({
          'fr': {'level': 2, 'xp_offset': 300},
          'fr-CA': {'level': 3, 'xp_offset': 500},
        }),
      );

      expect(profile.languageAnalytics!['fr']!.xpOffset, 500);
    });

    test('a non-integer level or offset does not throw', () {
      final profile = AnalyticsProfileModel.fromJson(
        profileJson({
          'fr': {'level': 'three', 'xp_offset': 1.5},
        }),
      );

      expect(profile.languageAnalytics!['fr']!.level, 0);
      expect(profile.languageAnalytics!['fr']!.xpOffset, 0);
    });

    test('target language and map keys agree, so level resolves', () {
      // Before #8582 the target was serialized short while the keys were
      // written full, so `level` read null for every learner whose target was
      // a regional variant — publishing them to classmates as level 0.
      final profile = AnalyticsProfileModel.fromJson(
        profileJson({
          'fr-CA': {'level': 13, 'xp_offset': 0},
        }),
      );

      expect(profile.targetLanguage, 'fr');
      expect(profile.level, 13);
    });

    test('survives a language list that has not loaded', () {
      // Entries used to be resolved through PLanguageStore at parse time. The
      // store starts empty and fills asynchronously, so a parse that beat it
      // dropped every entry — and the next write published that empty result
      // over the learner's real history.
      final profile = AnalyticsProfileModel.fromJson(
        profileJson({
          'fr': {'level': 13, 'xp_offset': 0},
        }),
      );

      expect(profile.languageAnalytics!['fr']!.level, 13);
    });
  });

  group('writing', () {
    test('a level written for one language leaves the others alone', () {
      // The defect behind "switched to Dutch, saw my French level": the level
      // used to be filed under whatever the target language happened to be
      // when the write ran, rather than the language it was computed from.
      final profile = AnalyticsProfileModel(
        languageAnalytics: {
          'fr': LanguageAnalyticsProfileEntry(13, 0),
          'nl': LanguageAnalyticsProfileEntry(2, 0),
        },
      );

      profile.setLanguageInfo('nl', 3, null);

      expect(profile.languageAnalytics!['fr']!.level, 13);
      expect(profile.languageAnalytics!['nl']!.level, 3);
    });

    test('a regional variant writes onto its language', () {
      final profile = AnalyticsProfileModel(
        languageAnalytics: {'fr': LanguageAnalyticsProfileEntry(13, 0)},
      );

      profile.setLanguageInfo('fr-CA', 14, null);

      expect(profile.languageAnalytics!.keys, ['fr']);
      expect(profile.languageAnalytics!['fr']!.level, 14);
    });

    test('a level may fall, because blocking constructs lowers it', () {
      final profile = AnalyticsProfileModel(
        languageAnalytics: {'fr': LanguageAnalyticsProfileEntry(13, 0)},
      );

      profile.setLanguageInfo('fr', 9, null);

      expect(profile.languageAnalytics!['fr']!.level, 9);
    });

    test('an unknown analytics room id leaves a known one alone', () {
      // Null means "not known here" — most often the room simply has not
      // surfaced in sync yet. Instructor analytics access is granted through
      // this id, so dropping it costs that student's instructors their access.
      final profile = AnalyticsProfileModel(
        languageAnalytics: {
          'fr': LanguageAnalyticsProfileEntry(13, 0, analyticsRoomId: '!a:x'),
        },
      );

      profile.setLanguageInfo('fr', 14, null);

      expect(profile.languageAnalytics!['fr']!.analyticsRoomId, '!a:x');
      expect(profile.languageAnalytics!['fr']!.level, 14);
    });

    test('a full code assigned to target language is normalized', () {
      // The short-code grain is the whole point of this class: a full code
      // stored here reads back as a missing entry, which is the #8582 bug.
      final profile = AnalyticsProfileModel(
        targetLanguage: 'fr-CA',
        baseLanguage: 'en-US',
        languageAnalytics: {'fr': LanguageAnalyticsProfileEntry(13, 0)},
      );

      expect(profile.targetLanguage, 'fr');
      expect(profile.baseLanguage, 'en');
      expect(profile.level, 13);

      profile.targetLanguage = 'es-MX';
      expect(profile.targetLanguage, 'es');
    });

    test('round-trips through json as short codes', () {
      final profile = AnalyticsProfileModel.fromJson(
        profileJson({
          'fr-CA': {'level': 13, 'xp_offset': 2, 'analytics_room_id': '!a:x'},
        }),
      );

      final json = profile.toJson();
      expect(json['analytics'].keys, ['fr']);
      expect(json['target_language'], 'fr');

      final reparsed = AnalyticsProfileModel.fromJson({
        PangeaEventTypes.profileAnalytics: json,
      });
      expect(reparsed.level, 13);
      expect(reparsed.xpOffsetByLanguage('fr-CA'), 2);
      expect(reparsed.analyticsRoomIdByLanguage('fr-FR'), '!a:x');
    });
  });
}
