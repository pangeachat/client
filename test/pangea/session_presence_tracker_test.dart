import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/activity_sessions/session_presence_tracker.dart';
import 'get_test_client.dart';

/// Who is around on the join list and in the waiting room (#9333): the shared
/// recent-first order, and the online count / last-active time read from the
/// presence the tracker watches.
void main() {
  group('compareRecentFirst', () {
    final early = DateTime(2026, 1, 1, 9);
    final late = DateTime(2026, 1, 1, 10);

    test('orders most recent first, unknown last', () {
      final times = [early, null, late, null, early];
      times.sort(SessionPresenceTracker.compareRecentFirst);
      expect(times, [late, early, early, null, null]);
    });

    test('equal times and two unknowns compare equal', () {
      expect(SessionPresenceTracker.compareRecentFirst(early, early), 0);
      expect(SessionPresenceTracker.compareRecentFirst(null, null), 0);
    });
  });

  group('onlineCount / lastActiveOf', () {
    const bot = '@bot:example.org';
    const ana = '@ana:example.org';
    const ben = '@ben:example.org';
    const cy = '@cy:example.org';

    late Client client;
    late SessionPresenceTracker tracker;

    setUpAll(() async {
      // The bot filter reads BotName.byEnvironment (GetStorage + dotenv).
      TestWidgetsFlutterBinding.ensureInitialized();
      final tempDir = await Directory.systemTemp.createTemp('presence');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (methodCall) async => tempDir.path,
          );
      await GetStorage.init('env_override');
      dotenv.testLoad(mergeWith: {'BOT_NAME': bot});
    });

    setUp(() async {
      client = await getTestClient();
      tracker = SessionPresenceTracker(client);
    });

    tearDown(() async {
      tracker.dispose();
      await client.dispose();
    });

    Future<void> push(
      String userId,
      PresenceType presence, {
      int? lastActiveAgoMs,
      bool? currentlyActive,
    }) async {
      client.onPresenceChanged.add(
        CachedPresence(
          presence,
          lastActiveAgoMs,
          null,
          currentlyActive,
          userId,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    test('nothing known means no one online and no last-active time', () async {
      await tracker.watch([ana, ben], cachedOnly: true);
      expect(tracker.onlineCount([ana, ben]), 0);
      expect(tracker.lastActiveOf([ana, ben]), isNull);
    });

    test('counts online watched users from presence updates', () async {
      await tracker.watch([ana, ben, cy], cachedOnly: true);
      await push(ana, PresenceType.online, currentlyActive: true);
      await push(ben, PresenceType.online, lastActiveAgoMs: 1000);
      await push(cy, PresenceType.offline, lastActiveAgoMs: 60000);
      expect(tracker.onlineCount([ana, ben, cy]), 2);
      expect(tracker.onlineCount([cy]), 0);
    });

    test('ignores updates for users it does not watch', () async {
      await tracker.watch([ana], cachedOnly: true);
      await push(ben, PresenceType.online, currentlyActive: true);
      expect(tracker.onlineCount([ben]), 0);
    });

    test('the bot is never watched', () async {
      await tracker.watch([bot], cachedOnly: true);
      await push(bot, PresenceType.online, currentlyActive: true);
      expect(tracker.onlineCount([bot]), 0);
    });

    test(
      'last active is the latest of the group; currently active is now',
      () async {
        await tracker.watch([ana, ben], cachedOnly: true);
        await push(ana, PresenceType.offline, lastActiveAgoMs: 3600 * 1000);
        await push(ben, PresenceType.offline, lastActiveAgoMs: 60 * 1000);
        final benAt = tracker.lastActiveOf([ben])!;
        expect(tracker.lastActiveOf([ana, ben]), benAt);
        expect(tracker.lastActiveOf([ana])!.isBefore(benAt), isTrue);

        await push(ana, PresenceType.online, currentlyActive: true);
        final now = DateTime(2030);
        expect(tracker.lastActiveOf([ana, ben], now: now), now);
      },
    );
  });
}
