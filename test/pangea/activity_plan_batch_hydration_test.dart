import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// Hydration travels in ONE request per screen.
///
/// A course screen shows one activity per session room and used to fetch one
/// plan per room, which is what made a single screen cost dozens of round trips
/// (devops postmortem 2026-08-04, action A5). The queue now drains into
/// `POST /v2/activity/batch`.
///
/// The properties worth defending are the ones a naive batching would quietly
/// drop: a removed activity must still be recorded as removed, a failed read
/// must stay retryable rather than be taken as a verdict, and known-dead ids
/// must not travel at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('plan_batch_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  var clock = DateTime(2026, 9, 13, 12);
  final repo = ActivityPlanRepo.instance;

  setUpAll(() async {
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('activity_plan_storage');
  });

  setUp(() {
    clock = DateTime(2026, 9, 13, 12);
    ActivityPlanRepo.now = () => clock;
    repo.resetBackoff();
  });

  tearDownAll(() => ActivityPlanRepo.now = DateTime.now);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Map<String, dynamic> planBody(String id) => {
    'activity_id': id,
    'roles': [
      {'role_id': 'r1', 'name': 'Cliente'},
    ],
  };

  /// Runs [body] against a mock backend, recording every request that left.
  Future<List<http.Request>> capture(
    Future<http.Response> Function(http.Request) handler,
    Future<void> Function() body,
  ) async {
    final seen = <http.Request>[];
    await http.runWithClient(body, () {
      return MockClient((request) {
        seen.add(request);
        return handler(request);
      });
    });
    return seen;
  }

  Future<http.Response> batchOf({
    List<String> found = const [],
    List<String> removed = const [],
    List<String> unavailable = const [],
  }) async => http.Response(
    jsonEncode({
      'activities': {
        for (final id in found)
          id: {'plan': planBody(id), 'l1': 'en', 'version_id': 'v1'},
      },
      'removed': removed,
      'unavailable': unavailable,
    }),
    200,
  );

  group('one screen is one request', () {
    test('a queued backlog drains into a single batch call', () async {
      final ids = [for (var i = 0; i < 12; i++) 'batch-$i'];

      final requests = await capture((_) => batchOf(found: ids), () async {
        for (final id in ids) {
          repo.ensure(id, l1: 'en');
        }
        await settle();
      });

      expect(
        requests.length,
        1,
        reason: '12 activities used to cost 12 round trips',
      );
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, endsWith('/v2/activity/batch'));

      final sent = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect((sent['activity_ids'] as List).length, 12);
      expect(sent['l1'], 'en');
    });

    test('every plan in the batch lands in the cache', () async {
      final ids = ['land-a', 'land-b', 'land-c'];

      await capture((_) => batchOf(found: ids), () async {
        for (final id in ids) {
          repo.ensure(id, l1: 'en');
        }
        await settle();
      });

      for (final id in ids) {
        expect(
          repo.cachedPlan(id, l1: 'en')?.activityId,
          id,
          reason: 'a batched read must populate the cache the single read does',
        );
      }
    });

    test('a pinned version rides along per activity', () async {
      final requests = await capture(
        (_) => batchOf(found: ['pin-a']),
        () async {
          repo.ensure('pin-a', l1: 'en', version: 'v' * 32);
          repo.ensure('pin-b', l1: 'en');
          await settle();
        },
      );

      final sent = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(sent['versions'], {'pin-a': 'v' * 32});
    });
  });

  group('one activity cannot speak for another', () {
    test('a removed id is recorded, its batch-mates are not', () async {
      final requests = await capture(
        (_) => batchOf(found: ['keep-1'], removed: ['gone-1']),
        () async {
          repo.ensure('keep-1', l1: 'en');
          repo.ensure('gone-1', l1: 'en');
          await settle();
        },
      );
      expect(requests.length, 1);

      expect(await repo.isConfirmedRemoved('gone-1'), isTrue);
      expect(await repo.isConfirmedRemoved('keep-1'), isFalse);
      expect(repo.cachedPlan('keep-1', l1: 'en'), isNotNull);
    });

    test('an unavailable id is retryable, never recorded as removed', () async {
      // Both outcomes render as "no plan". Treating a failed read as a verdict
      // would let a backend outage mark a live catalog as deleted.
      await capture(
        (_) => batchOf(found: ['ok-1'], unavailable: ['flaky-1']),
        () async {
          repo.ensure('ok-1', l1: 'en');
          repo.ensure('flaky-1', l1: 'en');
          await settle();
        },
      );

      expect(await repo.isConfirmedRemoved('flaky-1'), isFalse);
    });
  });

  group('known-dead ids never travel', () {
    test('a confirmed-removed id is dropped before the request', () async {
      await capture((_) => batchOf(removed: ['dead-1']), () async {
        repo.ensure('dead-1', l1: 'en');
        await settle();
      });
      expect(await repo.isConfirmedRemoved('dead-1'), isTrue);

      // Past the attempt cooldown, so only the removed verdict can suppress it.
      clock = clock.add(const Duration(seconds: 61));

      final later = await capture((_) => batchOf(found: ['live-1']), () async {
        repo.ensure('dead-1', l1: 'en');
        repo.ensure('live-1', l1: 'en');
        await settle();
      });

      final sent = jsonDecode(later.single.body) as Map<String, dynamic>;
      expect(
        sent['activity_ids'],
        ['live-1'],
        reason:
            'asking again for an id the backend already called gone is the '
            'CLIENT-EB0 loop — batching must not reopen it',
      );
    });
  });

  group('what a batch must not conflate', () {
    test('one activity at two versions is split across requests', () async {
      // The wire format keys pinned versions by activity id, so the same
      // activity at two versions cannot both be expressed — and the one plan
      // that came back would be cached under BOTH version keys, scoring a
      // learner against a version they were never pinned to.
      final requests = await capture((_) => batchOf(found: ['dual']), () async {
        repo.ensure('dual', l1: 'en', version: 'a' * 32);
        repo.ensure('dual', l1: 'en', version: 'b' * 32);
        await settle();
        await settle();
      });

      for (final r in requests) {
        final ids =
            ((jsonDecode(r.body) as Map<String, dynamic>)['activity_ids']
                    as List)
                .cast<String>();
        expect(
          ids.length,
          ids.toSet().length,
          reason: 'an activity may appear at most once per request',
        );
      }
      expect(requests.length, greaterThan(1));
    });

    test('a cached plan is not re-fetched', () async {
      await capture((_) => batchOf(found: ['warm-1']), () async {
        repo.ensure('warm-1', l1: 'en');
        await settle();
      });
      expect(repo.cachedPlan('warm-1', l1: 'en'), isNotNull);

      // A fresh session: the resolved-plan map is empty but the TTL cache is
      // not, which is exactly the cold-start shape.
      final next = ActivityPlanRepo.forTesting();
      clock = clock.add(const Duration(seconds: 61));
      final requests = await capture(
        (_) => batchOf(found: ['warm-1']),
        () async {
          next.ensure('warm-1', l1: 'en');
          await settle();
        },
      );

      expect(
        requests,
        isEmpty,
        reason: 'spending allowance to receive a plan already on disk',
      );
      expect(next.cachedPlan('warm-1', l1: 'en'), isNotNull);
    });

    test('a direct read joins an in-flight batch instead of racing it', () async {
      final requests = await capture(
        (_) => batchOf(found: ['join-1']),
        () async {
          repo.ensure('join-1', l1: 'en');
          // Opening the activity while its card is still hydrating.
          final direct = repo.lookup('join-1', l1: 'en');
          await settle();
          final result = await direct;
          expect(result.status, ActivityPlanLookupStatus.found);
        },
      );

      expect(
        requests.length,
        1,
        reason:
            'a second request for the same plan spends the allowance twice and '
            'exposes the direct read to a throttle the batch already survived',
      );
    });
  });

  group('a batch carries one display language', () {
    test('a differing l1 is cut into its own request', () async {
      final requests = await capture(
        (_) => batchOf(found: ['en-1', 'en-2', 'fr-1']),
        () async {
          repo.ensure('en-1', l1: 'en');
          repo.ensure('en-2', l1: 'en');
          repo.ensure('fr-1', l1: 'fr');
          await settle();
        },
      );

      final langs = requests
          .map((r) => (jsonDecode(r.body) as Map<String, dynamic>)['l1'])
          .toList();
      expect(langs, containsAll(['en', 'fr']));
      for (final r in requests) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final ids = (body['activity_ids'] as List).cast<String>();
        expect(
          ids.every((id) => id.startsWith(body['l1'] as String)),
          isTrue,
          reason: 'a batch applies one l1 to every activity in it',
        );
      }
    });
  });
}
