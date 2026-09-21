import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// Regression: Sentry CLIENT-EFH + CLIENT-CY3 (#8691) — the quest half of the
/// CLIENT-EB0 loop. The outline memo (#8358) and the per-room report throttle
/// (#8083) already cap a dead quest at one fetch + one report per app session,
/// but both are in-memory, so every NEW session re-fetched and re-reported
/// every known-dead quest id (~7 events/user/day across the two issues).
///
/// What is pinned here: the confirmed-404 verdict persists across sessions
/// ([QuestRepo.removedQuests]); [QuestRepo.quest] owns the one report (once
/// per quest id per session, only on an actual fetch) and
/// [reportCourseOutlineFailure] no longer re-reports a missing quest per
/// course room; forceRefresh bypasses the verdict and a success clears it;
/// and [QuestPlansRepo.get] shares the same verdict space.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('quest_removed_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  var clock = DateTime(2026, 9, 1, 12);

  setUpAll(() async {
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('quest_removed_storage');
  });

  setUp(() async {
    clock = DateTime(2026, 9, 1, 12);
    QuestRepo.now = () => clock;
    ErrorHandler.resetReportedOnceKeysForTest();
    // Wipe the persisted verdicts, then start from a fresh cache instance, so
    // tests cannot leak verdicts into each other through the shared box.
    await GetStorage('quest_removed_storage').erase();
    QuestRepo.removedQuests = QuestRepo.newRemovedQuestsCache();
  });

  tearDownAll(() => QuestRepo.now = DateTime.now);

  /// The next app session: a fresh cache instance (empty memory) over the
  /// same persisted box.
  void restart() {
    QuestRepo.removedQuests = QuestRepo.newRemovedQuestsCache();
  }

  /// Serves every top-level `http` call from [handler] while [body] runs, and
  /// reports how many requests actually left the client.
  Future<int> countingClient(
    Future<http.Response> Function(http.Request) handler,
    Future<void> Function() body,
  ) async {
    var requests = 0;
    await http.runWithClient(body, () {
      return MockClient((request) {
        requests++;
        return handler(request);
      });
    });
    return requests;
  }

  Future<http.Response> gone(http.Request _) async =>
      http.Response('{"errors":[{"message":"Not Found"}]}', 404);

  Future<http.Response> unavailable(http.Request _) async =>
      http.Response('{"errors":[{"message":"upstream down"}]}', 503);

  Future<http.Response> Function(http.Request) found(String questId) =>
      (http.Request _) async => http.Response('{"id":"$questId"}', 200);

  group('the confirmed-404 verdict survives an app restart', () {
    test(
      'quest() answers MissingQuestException from disk, no request',
      () async {
        const questId = 'gone-quest';

        final first = await countingClient(gone, () async {
          final result = await QuestRepo.quest(questId);
          expect(result.asError!.error, isA<MissingQuestException>());
        });
        expect(first, 1, reason: 'the first read must actually ask the CMS');

        restart();
        final later = await countingClient(gone, () async {
          final result = await QuestRepo.quest(questId);
          expect(result.asError!.error, isA<MissingQuestException>());
        });
        expect(
          later,
          0,
          reason:
              'the next session re-asked the CMS about a known-dead quest id — '
              'the CLIENT-EFH / CLIENT-CY3 loop itself',
        );
      },
    );

    test('only the 404 verdict persists — a 5xx stays retryable', () async {
      const questId = 'flaky-quest';

      await countingClient(gone, () async {
        await QuestRepo.quest('gone-neighbour-quest');
      });
      await countingClient(unavailable, () async {
        final result = await QuestRepo.quest(questId);
        expect(result.asError!.error, isNot(isA<MissingQuestException>()));
      });

      restart();
      expect(
        await countingClient(unavailable, () async {
          await QuestRepo.quest(questId);
        }),
        1,
        reason: 'a transient failure must never be remembered as removed',
      );
      expect(
        await countingClient(gone, () async {
          await QuestRepo.quest('gone-neighbour-quest');
        }),
        0,
      );
    });

    test('the verdict lapses after the retention window', () async {
      const questId = 'gone-until-retention-quest';

      await countingClient(gone, () async {
        await QuestRepo.quest(questId);
      });

      clock = clock.add(const Duration(hours: 25));
      restart();
      expect(
        await countingClient(gone, () async {
          await QuestRepo.quest(questId);
        }),
        1,
        reason:
            'the verdict must expire — a repaired quest has to come back '
            'without every user hard-refreshing',
      );
    });
  });

  group('forceRefresh is the explicit-refresh escape hatch', () {
    test('bypasses the remembered verdict, and a success clears it', () async {
      const questId = 'gone-then-restored-quest';

      await countingClient(gone, () async {
        await QuestRepo.quest(questId);
      });

      final refreshed = await countingClient(found(questId), () async {
        final result = await QuestRepo.quest(questId, forceRefresh: true);
        expect(result.asValue!.value.id, questId);
      });
      expect(refreshed, 1, reason: 'forceRefresh must never be suppressed');

      restart();
      expect(
        await countingClient(found(questId), () async {
          final result = await QuestRepo.quest(questId);
          expect(result.asValue!.value.id, questId);
        }),
        1,
        reason:
            'the success must have cleared the persisted verdict — a restored '
            'quest is fetched normally on the next session',
      );
    });
  });

  group('a quest 404 reports once per id per session, at the fetch', () {
    test('the fetch spends the once-per-id key', () async {
      const questId = 'gone-once-key-quest';

      await countingClient(gone, () async {
        await QuestRepo.quest(questId);
      });

      expect(
        await ErrorHandler.logErrorOnce(
          key: 'quest-plan-404:$questId',
          e: MissingQuestException(),
          data: const {},
        ),
        isFalse,
        reason:
            'the 404 fetch must have reported through this key already — a '
            'second report on it within the session is pure event volume',
      );
    });

    test('a 5xx does not spend the once key', () async {
      const questId = 'flaky-no-once-key-quest';

      await countingClient(unavailable, () async {
        await QuestRepo.quest(questId);
      });

      expect(
        await ErrorHandler.logErrorOnce(
          key: 'quest-plan-404:$questId',
          e: MissingQuestException(),
          data: const {},
        ),
        isTrue,
        reason: 'only the confirmed-404 path is capped to once per id',
      );
    });

    test('the rebuild reporter no longer re-reports a missing quest', () async {
      // The repo owns the missing-quest report now; the per-room reporter
      // re-reporting it on every session's first rebuild was the residual
      // CLIENT-EFH / CLIENT-CY3 volume.
      expect(
        await reportCourseOutlineFailure(
          '!room:server',
          'quest-1',
          MissingQuestException(),
          StackTrace.current,
        ),
        isFalse,
      );
      // And skipping it must not spend the room's throttle key: a room's
      // OTHER failures are still owed their one report.
      expect(
        await reportCourseOutlineFailure(
          '!room:server',
          'quest-1',
          Exception('choreo unreachable'),
          StackTrace.current,
        ),
        isTrue,
      );
    });
  });

  group('QuestPlansRepo shares the verdict space', () {
    test('get() answers null for a known-dead id, no request', () async {
      const questId = 'gone-shared-quest';

      await countingClient(gone, () async {
        await QuestRepo.quest(questId);
      });

      final later = await countingClient(gone, () async {
        expect(await QuestPlansRepo.get(questId), isNull);
      });
      expect(later, 0);
    });

    test('get()\'s own 404 marks the id for every reader', () async {
      const questId = 'gone-via-picker-quest';

      final first = await countingClient(gone, () async {
        expect(await QuestPlansRepo.get(questId), isNull);
      });
      expect(first, 1);

      restart();
      expect(
        await countingClient(gone, () async {
          final result = await QuestRepo.quest(questId);
          expect(result.asError!.error, isA<MissingQuestException>());
        }),
        0,
      );
    });
  });
}
