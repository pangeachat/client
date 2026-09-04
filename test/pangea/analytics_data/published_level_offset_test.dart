import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'analytics_fixtures.dart';

/// #8582: the level published to the public analytics profile has to be the
/// SAME number the learner's own analytics bar renders.
///
/// The bar renders [DerivedAnalyticsDataModel.level], which is computed over
/// totalXP PLUS the language's XP offset. `_recomputeTotalXP` used to publish
/// `calculateLevelWithXp(totalXP)` — the raw total, offset dropped — so any
/// learner carrying an offset (anyone whose level protection has engaged after
/// wrong practice answers) saw a profile level below their own bar, rewritten
/// on every sync round-trip. It now stores the total and publishes the level
/// the STORE reports, which is what these tests pin.
void main() {
  sqfliteFfiInit();

  test(
    'the stored level counts the XP offset, so it matches the bar',
    () async {
      final db = await freshDatabase();

      // 900 XP alone is level 3; the offset carries it to 4. Publishing the raw
      // total would have said 3 while the bar said 4.
      await db.updateTotalXP(900, testLang);
      await db.updateXPOffset(600, testLang);

      final stats = await db.getDerivedStats(testLang);

      expect(stats.totalXP, 1500);
      expect(stats.level, DerivedAnalyticsDataModel.calculateLevelWithXp(1500));
      expect(
        stats.level,
        greaterThan(DerivedAnalyticsDataModel.calculateLevelWithXp(900)),
        reason: 'an offset that changes the level is the case that regressed',
      );
    },
  );

  test('storing a new total preserves the offset', () async {
    final db = await freshDatabase();

    await db.updateXPOffset(600, testLang);
    // _recomputeTotalXP writes the total and then reads the level back; the
    // offset must survive that write or the read reports the raw level again.
    await db.updateTotalXP(900, testLang);

    final stats = await db.getDerivedStats(testLang);
    expect(stats.offset, 600);
    expect(stats.totalXP, 1500);
  });

  test('each language keeps its own total and offset', () async {
    final db = await freshDatabase();

    await db.updateTotalXP(900, 'es');
    await db.updateXPOffset(600, 'es');
    await db.updateTotalXP(100, 'fr');

    expect((await db.getDerivedStats('es')).totalXP, 1500);
    expect((await db.getDerivedStats('fr')).totalXP, 100);
  });
}
