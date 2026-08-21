import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics_data/analytics_database.dart';
import 'analytics_fixtures.dart';

/// #8525: a closed analytics store used to fail one doomed call at a time, so
/// the 5-minute analytics timer produced a Sentry event every tick for the
/// life of the session. [AnalyticsDatabase] now carries explicit closed state
/// and reports it as a single typed exception, which is the signal the update
/// service uses to stop retrying.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AnalyticsDatabase db;

  setUp(() async {
    db = await freshDatabase();
  });

  group('close initiated by us', () {
    test('a fresh database is not closed', () {
      expect(db.isClosed, isFalse);
    });

    test('delete() marks the store closed', () async {
      await db.delete();

      expect(db.isClosed, isTrue);
    });

    test(
      'a write after delete() throws AnalyticsDatabaseClosedException',
      () async {
        await db.delete();

        await expectLater(
          db.clearLocalConstructData(testLang),
          throwsA(isA<AnalyticsDatabaseClosedException>()),
        );
      },
    );
  });

  group('close initiated elsewhere', () {
    test('a store closed out from under us surfaces as '
        'AnalyticsDatabaseClosedException, not a raw store error', () async {
      // Close the underlying store directly, leaving this instance believing
      // it is still live — the shape of the production failure, where
      // something other than delete() closed the connection.
      expect(db.isClosed, isFalse);
      await db.database?.close();

      await expectLater(
        db.clearLocalConstructData(testLang),
        throwsA(isA<AnalyticsDatabaseClosedException>()),
      );
    });

    test(
      'the external close is latched, so the next call fails fast',
      () async {
        await db.database?.close();

        await expectLater(
          db.clearLocalConstructData(testLang),
          throwsA(isA<AnalyticsDatabaseClosedException>()),
        );

        // Latched by the first failure: this is what stops a caller from
        // issuing another doomed request every tick.
        expect(db.isClosed, isTrue);

        await expectLater(
          db.clearLocalConstructData(testLang),
          throwsA(isA<AnalyticsDatabaseClosedException>()),
        );
      },
    );
  });
}
