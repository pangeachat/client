import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_request.dart';
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

  group('the rules the batch advertises', () {
    test('a queue larger than one batch is split at the cap', () async {
      final ids = [for (var i = 0; i < 51; i++) 'cap-$i'];

      final requests = await capture((_) => batchOf(found: ids), () async {
        for (final id in ids) {
          repo.ensure(id, l1: 'en');
        }
        await settle();
        await settle();
      });

      final sentIds = <String>[];
      for (final r in requests) {
        final batch =
            ((jsonDecode(r.body) as Map<String, dynamic>)['activity_ids']
                    as List)
                .cast<String>();
        expect(
          batch.length,
          lessThanOrEqualTo(50),
          reason: 'the backend rejects an oversized batch as a 422',
        );
        sentIds.addAll(batch);
      }
      expect(sentIds.length, sentIds.toSet().length);
    });

    test('in-flight work is bounded by activities, not by requests', () async {
      // Each activity in a batch costs the allowance what it would have cost
      // alone, so counting batches would bound nothing that matters: six
      // batches of 50 is 300 activities from one frame, past the whole minute's
      // allowance, while reading as a tighter bound than the per-read one it
      // replaced.
      final gate = Completer<void>();
      final ids = [for (var i = 0; i < 120; i++) 'flood-$i'];
      final sent = <String>[];

      await http.runWithClient(
        () async {
          for (final id in ids) {
            repo.ensure(id, l1: 'en');
          }
          await settle();

          expect(
            sent.length,
            lessThanOrEqualTo(50),
            reason:
                '120 keys offered at once must not all be in flight before a '
                'single response has come back',
          );

          gate.complete();
          await settle();
        },
        () {
          return MockClient((request) async {
            sent.addAll(
              ((jsonDecode(request.body)
                          as Map<String, dynamic>)['activity_ids']
                      as List)
                  .cast<String>(),
            );
            await gate.future;
            return batchOf(found: ids);
          });
        },
      );

      expect(sent, isNotEmpty);
    });

    test('a cache hit does not renew the plan\'s freshness', () async {
      // Restamping content that came off disk unchanged would extend its TTL
      // without anyone re-reading it, so a stale plan could outlive its hour
      // indefinitely across frequent restarts. Asserted on the persisted
      // timestamp because the TTL is measured against real wall-clock, which
      // the repo's clock seam does not drive.
      await capture((_) => batchOf(found: ['ttl-1']), () async {
        repo.ensure('ttl-1', l1: 'en');
        await settle();
      });

      final box = GetStorage('activity_plan_storage');
      final key = ActivityPlanFetchRequest(
        activityId: 'ttl-1',
        l1: 'en',
      ).storageKey;
      final stamped = (box.read(key) as Map)['timestamp'] as int;

      // A fresh session serves it from disk rather than the network.
      final next = ActivityPlanRepo.forTesting();
      final requests = await capture(
        (_) => batchOf(found: ['ttl-1']),
        () async {
          next.ensure('ttl-1', l1: 'en');
          await settle();
        },
      );
      expect(requests, isEmpty, reason: 'precondition: served from cache');

      expect(
        (box.read(key) as Map)['timestamp'],
        stamped,
        reason: 'only a network response earns a new timestamp',
      );
    });

    test('a batch never exceeds the free in-flight capacity', () async {
      // Taking a full batch while activities are still hydrating would put more
      // in flight than the bound allows — the bound this loop exists to hold.
      final gate = Completer<void>();
      final sent = <String>[];

      await http.runWithClient(
        () async {
          for (var i = 0; i < 30; i++) {
            repo.ensure('cap-a-$i', l1: 'en');
          }
          await settle();
          expect(sent.length, 30);

          // A second frame offers 50 more while the first 30 are still in flight.
          for (var i = 0; i < 50; i++) {
            repo.ensure('cap-b-$i', l1: 'en');
          }
          await settle();
          expect(
            sent.length,
            lessThanOrEqualTo(50),
            reason:
                '30 in flight leaves room for 20, not for another full batch',
          );

          gate.complete();
          await settle();
        },
        () {
          return MockClient((request) async {
            sent.addAll(
              ((jsonDecode(request.body)
                          as Map<String, dynamic>)['activity_ids']
                      as List)
                  .cast<String>(),
            );
            await gate.future;
            return batchOf();
          });
        },
      );
    });

    test('an unsatisfied key does not fall back to its own request', () async {
      // The prefetch fills the cache and the ordinary read serves from it. A
      // key the batch did not satisfy has no cache entry, so reading it would
      // send a request of its own — the fan-out this path exists to remove,
      // arriving by the back door on exactly the degraded responses where it
      // hurts most.
      final requests = await capture(
        (_) => batchOf(found: ['got-1'], unavailable: ['missed-1', 'missed-2']),
        () async {
          repo.ensure('got-1', l1: 'en');
          repo.ensure('missed-1', l1: 'en');
          repo.ensure('missed-2', l1: 'en');
          await settle();
          await settle();
        },
      );

      expect(
        requests.length,
        1,
        reason: 'two unsatisfied keys must not become two more requests',
      );
      expect(repo.cachedPlan('got-1', l1: 'en'), isNotNull);
    });

    test(
      'a cached activity does not wait on someone else\'s network read',
      () async {
        // A batch registers every key it was given, but the prefetch asks only
        // for the ones it could not already answer. Joining before checking the
        // cache would make a cached activity wait out an unrelated key's request
        // — up to the full timeout — to return something it had all along.
        await capture((_) => batchOf(found: ['ready-1']), () async {
          repo.ensure('ready-1', l1: 'en');
          await settle();
          await settle();
        });
        expect(repo.cachedPlan('ready-1', l1: 'en'), isNotNull);

        // A COLD instance: the TTL cache holds 'ready-1' but nothing is
        // resolved in memory, which is what makes `ensure` offer it to a
        // batch at all — a resolved plan is declined before it ever queues.
        final cold = ActivityPlanRepo.forTesting();
        final gate = Completer<void>();
        await http.runWithClient(
          () async {
            // 'slow-1' goes to the network; 'ready-1' is already cached.
            cold.ensure('slow-1', l1: 'en');
            cold.ensure('ready-1', l1: 'en');
            await settle();

            final served = await cold
                .lookup('ready-1', l1: 'en')
                .timeout(
                  const Duration(seconds: 2),
                  onTimeout: () =>
                      throw StateError('a cached read waited on the network'),
                );
            expect(served.status, ActivityPlanLookupStatus.found);

            gate.complete();
            await settle();
          },
          () {
            return MockClient((request) async {
              await gate.future;
              return batchOf(found: ['slow-1']);
            });
          },
        );
      },
    );

    test('a failed batch is shared, not re-asked by every joiner', () async {
      // Falling through to a fetch would send one request per joining caller at
      // the exact moment the backend is already failing.
      final gate = Completer<void>();
      var requests = 0;

      await http.runWithClient(
        () async {
          for (var i = 0; i < 5; i++) {
            repo.ensure('down-$i', l1: 'en');
          }
          await settle();

          final joiners = [
            for (var i = 0; i < 5; i++) repo.lookup('down-$i', l1: 'en'),
          ];
          gate.complete();
          final results = await Future.wait(joiners);

          for (final r in results) {
            expect(r.status, ActivityPlanLookupStatus.failed);
            expect(
              r.status,
              isNot(ActivityPlanLookupStatus.removed),
              reason:
                  'a failed read is not a verdict that the activity is gone',
            );
          }
          await settle();
        },
        () {
          return MockClient((request) async {
            requests++;
            await gate.future;
            return batchOf(
              unavailable: [for (var i = 0; i < 5; i++) 'down-$i'],
            );
          });
        },
      );

      expect(
        requests,
        1,
        reason: 'five joiners on a failed batch must not become five requests',
      );
    });

    test('an unmappable body is recorded, not skipped in silence', () async {
      // The body came back but will not map, so the cache policy rejects it.
      // Without recording that, a caller already awaiting the batch finds no
      // outcome and sends its own request for the same unmappable plan.
      final requests = await capture(
        (_) async {
          return http.Response(
            jsonEncode({
              'activities': {
                // No `roles` — `shouldCache` refuses a body whose mapping throws.
                'bad-1': {
                  'plan': {'activity_id': 'bad-1', 'roles': 'not-a-list'},
                  'l1': 'en',
                  'version_id': 'v1',
                },
              },
              'removed': <String>[],
              'unavailable': <String>[],
            }),
            200,
          );
        },
        () async {
          repo.ensure('bad-1', l1: 'en');
          await settle();
          final joined = await repo.lookup('bad-1', l1: 'en');
          expect(joined.status, ActivityPlanLookupStatus.failed);
          await settle();
        },
      );

      expect(
        requests.length,
        1,
        reason: 'a rejected body must not become a second request for it',
      );
      expect(
        await repo.isConfirmedRemoved('bad-1'),
        isFalse,
        reason: 'unmappable is not a verdict that the activity is gone',
      );
    });

    test('a cache-served hydration releases the attempt park', () async {
      // `ensure` parks a key before it queues. The network path clears that on
      // success; the cache path must too. A plan with less than the cooldown
      // left on its TTL hydrates fine from cache, but a park left in place
      // means that when the entry does expire, `ensure` refuses to reload it
      // for the rest of the minute and the card simply empties.
      await capture((_) => batchOf(found: ['park-1']), () async {
        repo.ensure('park-1', l1: 'en');
        await settle();
        await settle();
      });

      // A cold instance hydrates the same key from disk — the cache path.
      final cold = ActivityPlanRepo.forTesting();
      await capture((_) => batchOf(found: ['park-1']), () async {
        cold.ensure('park-1', l1: 'en');
        await settle();
        await settle();
      });
      expect(cold.cachedPlan('park-1', l1: 'en'), isNotNull);

      // Stand in for the entry expiring: drop it, then let `cachedPlan` clear
      // the resolved copy so `ensure` is deciding on the park alone.
      final request = ActivityPlanFetchRequest(activityId: 'park-1', l1: 'en');
      await cold.invalidate(request);
      expect(cold.cachedPlan('park-1', l1: 'en'), isNull);

      expect(
        cold.ensure('park-1', l1: 'en'),
        isTrue,
        reason:
            'the cache hydration succeeded, so nothing should still be holding '
            'this key back from reloading once its plan is gone',
      );
    });

    test('a refresh travels alone', () async {
      // The read cannot express "ignore your cache for this one and not those",
      // so grouping a revalidate would silently downgrade it to a normal read.
      final requests = await capture(
        (_) => batchOf(found: ['solo-1', 'plain-1', 'plain-2']),
        () async {
          repo.ensure('plain-1', l1: 'en');
          repo.ensure('solo-1', l1: 'en', revalidate: true);
          repo.ensure('plain-2', l1: 'en');
          await settle();
          await settle();
        },
      );

      final withSolo = requests.where(
        (r) =>
            ((jsonDecode(r.body) as Map<String, dynamic>)['activity_ids']
                    as List)
                .contains('solo-1'),
      );
      expect(withSolo, hasLength(1));
      expect(
        ((jsonDecode(withSolo.single.body)
                    as Map<String, dynamic>)['activity_ids']
                as List)
            .length,
        1,
      );
    });

    test(
      'an unavailable id is asked for again once its cooldown lapses',
      () async {
        await capture((_) => batchOf(unavailable: ['retry-me']), () async {
          repo.ensure('retry-me', l1: 'en');
          await settle();
        });
        expect(await repo.isConfirmedRemoved('retry-me'), isFalse);

        clock = clock.add(const Duration(seconds: 61));
        final later = await capture(
          (_) => batchOf(found: ['retry-me']),
          () async {
            repo.ensure('retry-me', l1: 'en');
            await settle();
          },
        );

        expect(
          ((jsonDecode(later.single.body)
                  as Map<String, dynamic>)['activity_ids']
              as List),
          contains('retry-me'),
          reason: 'a failed read is transient — the id must stay eligible',
        );
      },
    );
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
