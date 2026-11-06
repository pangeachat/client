import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics_data/analytics_database.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
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
          db.clearLocalConstructData(testLang, batchKeys: const []),
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
        db.clearLocalConstructData(testLang, batchKeys: const []),
        throwsA(isA<AnalyticsDatabaseClosedException>()),
      );
    });

    test(
      'the external close is latched, so the next call fails fast',
      () async {
        await db.database?.close();

        await expectLater(
          db.clearLocalConstructData(testLang, batchKeys: const []),
          throwsA(isA<AnalyticsDatabaseClosedException>()),
        );

        // Latched by the first failure: this is what stops a caller from
        // issuing another doomed request every tick.
        expect(db.isClosed, isTrue);

        await expectLater(
          db.clearLocalConstructData(testLang, batchKeys: const []),
          throwsA(isA<AnalyticsDatabaseClosedException>()),
        );
      },
    );
  });

  /// #9802: reads skipped the closed-store check, so a read still running when
  /// sign-out deleted the store surfaced the browser's raw `InvalidStateError`
  /// and its caller reported it (CLIENT-F14, CLIENT-F5G).
  group('reads', () {
    const externalCloseCrumb =
        'AnalyticsDatabase: store closed externally; latched as closed';
    final crumbs = <String?>[];

    final closedBySignOut = isA<AnalyticsDatabaseClosedException>().having(
      (e) => e.closedBySignOut,
      'closedBySignOut',
      isTrue,
    );
    final closedElsewhere = isA<AnalyticsDatabaseClosedException>().having(
      (e) => e.closedBySignOut,
      'closedBySignOut',
      isFalse,
    );

    setUp(() async {
      crumbs.clear();
      await Sentry.init((options) {
        options.dsn = 'https://public@sentry.invalid/1';
        options.beforeBreadcrumb = (crumb, _) {
          crumbs.add(crumb?.message);
          return crumb;
        };
        options.beforeSend = (_, _) => null;
      });
    });

    tearDown(Sentry.close);

    test('a read after delete() throws AnalyticsDatabaseClosedException '
        'marked as sign-out', () async {
      await db.delete();

      await expectLater(db.getLocalUseLanguages(), throwsA(closedBySignOut));
      await expectLater(
        db.getConstructUses(const {}, testLang),
        throwsA(closedBySignOut),
      );
    });

    test('a read already running when delete() closes the store is marked as '
        'sign-out, and is not recorded as an external close', () async {
      // The connection goes first, as it does the moment the browser starts
      // deleting the store, so the read below fails once it reaches it.
      await db.database?.close();

      // Past the closed check and waiting on the store when delete() latches.
      final read = db.getLocalUseLanguages();
      final deleting = db.delete();

      await expectLater(read, throwsA(closedBySignOut));
      await deleting;
      expect(crumbs, isNot(contains(externalCloseCrumb)));
    });

    test('a read after an external close throws it unmarked, records the '
        'close and latches it', () async {
      await db.database?.close();

      await expectLater(db.getLocalUseLanguages(), throwsA(closedElsewhere));
      expect(crumbs, contains(externalCloseCrumb));
      expect(db.isClosed, isTrue);
      await expectLater(
        db.getConstructUses(const {}, testLang),
        throwsA(closedElsewhere),
      );
    });

    test('ErrorHandler.shouldReport drops a close made by sign-out and keeps '
        'any other', () async {
      final other = await freshDatabase(name: 'analytics_test_other');
      await db.delete();
      await other.database?.close();

      Future<Object> failure(Future<Object?> read) async {
        try {
          await read;
        } catch (e) {
          return e;
        }
        fail('expected the read to fail');
      }

      final bySignOut = await failure(db.getLocalUseLanguages());
      final elsewhere = await failure(other.getLocalUseLanguages());

      expect(ErrorHandler.shouldReport(bySignOut), isFalse);
      expect(ErrorHandler.shouldReport(elsewhere), isTrue);
    });
  });
}
