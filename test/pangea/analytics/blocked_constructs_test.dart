import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_sync_controller.dart';

/// Blocking and restoring vocab constructs (#6803).
///
/// Restore had no coverage at all before this: the settings event is the only
/// record of what is blocked, and its diff is the only thing that tells the app
/// a block was undone.
void main() {
  ConstructIdentifier id(String lemma) => ConstructIdentifier(
    lemma: lemma,
    type: ConstructTypeEnum.vocab,
    category: 'verb',
  );

  Map<String, dynamic> content(List<ConstructIdentifier> blocked) =>
      AnalyticsSettingsModel(blockedConstructs: blocked.toSet()).toJson();

  group('AnalyticsSettingsModel', () {
    test('round-trips the blocked set through JSON', () {
      final model = AnalyticsSettingsModel(
        blockedConstructs: {id('hablar'), id('comer')},
      );
      final restored = AnalyticsSettingsModel.fromJson(model.toJson());
      expect(restored.blockedConstructs, model.blockedConstructs);
    });

    test('absent key parses as an empty set, not null', () {
      expect(AnalyticsSettingsModel.fromJson({}).blockedConstructs, isEmpty);
    });

    test('copyWith replaces the set wholesale, which is how unblock works', () {
      final model = AnalyticsSettingsModel(
        blockedConstructs: {id('hablar'), id('comer')},
      );
      final remaining = model.blockedConstructs
          .where((c) => c != id('comer'))
          .toSet();

      expect(model.copyWith(blockedConstructs: remaining).blockedConstructs, {
        id('hablar'),
      });
      // The original is untouched — copyWith must not mutate in place, or the
      // "did anything actually change?" guard in unblockConstructs is blind.
      expect(model.blockedConstructs.length, 2);
    });
  });

  group('AnalyticsSyncController.diffAnalyticsSettings', () {
    test('a first-ever block has no prev_content and reads as an addition', () {
      final diff = AnalyticsSyncController.diffAnalyticsSettings(
        content([id('hablar')]),
        null,
      );
      expect(diff.blocked, {id('hablar')});
      expect(diff.restored, isEmpty);
    });

    test('adding to the set reports only the new one', () {
      final diff = AnalyticsSyncController.diffAnalyticsSettings(
        content([id('hablar'), id('comer')]),
        content([id('hablar')]),
      );
      expect(diff.blocked, {id('comer')});
      expect(diff.restored, isEmpty);
    });

    test('removing from the set reports a restore', () {
      // The regression this guards: computing additions only and bailing when
      // empty made an unblock a no-op everywhere downstream.
      final diff = AnalyticsSyncController.diffAnalyticsSettings(
        content([id('hablar')]),
        content([id('hablar'), id('comer')]),
      );
      expect(diff.blocked, isEmpty);
      expect(diff.restored, {id('comer')});
    });

    test('emptying the set restores every construct in it', () {
      final diff = AnalyticsSyncController.diffAnalyticsSettings(
        content([]),
        content([id('hablar'), id('comer')]),
      );
      expect(diff.restored, {id('hablar'), id('comer')});
    });

    test('one event can both block and restore', () {
      final diff = AnalyticsSyncController.diffAnalyticsSettings(
        content([id('comer')]),
        content([id('hablar')]),
      );
      expect(diff.blocked, {id('comer')});
      expect(diff.restored, {id('hablar')});
    });

    test('an unchanged set reports neither', () {
      final diff = AnalyticsSyncController.diffAnalyticsSettings(
        content([id('hablar')]),
        content([id('hablar')]),
      );
      expect(diff.blocked, isEmpty);
      expect(diff.restored, isEmpty);
    });
  });
}
