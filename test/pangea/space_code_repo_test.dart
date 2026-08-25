import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';

/// The cached-join-code TTL (#7524): an inbound join link's code is ferried
/// through GetStorage across the login bounce, so an entry cached long ago
/// (a visitor who never logged in, or an onboarding that never finished) must
/// not surprise-join a later login, possibly by a different account on a
/// shared browser. [SpaceCodeRepo.spaceCode] applies [SpaceCodeRepo.isFresh]
/// to the stored write stamp and clears stale entries on read; the boundary
/// logic is pinned here, along with the write's atomicity against a
/// concurrent read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpaceCodeRepo.isFresh', () {
    final now = DateTime(2026, 7, 7, 12);
    int writtenAgo(Duration ago) => now.subtract(ago).millisecondsSinceEpoch;

    test('a just-written entry is fresh', () {
      expect(SpaceCodeRepo.isFresh(writtenAgo(Duration.zero), now), isTrue);
    });

    test('an entry within the TTL is fresh', () {
      expect(
        SpaceCodeRepo.isFresh(writtenAgo(const Duration(minutes: 59)), now),
        isTrue,
      );
    });

    test('an entry older than the TTL is stale', () {
      expect(
        SpaceCodeRepo.isFresh(
          writtenAgo(SpaceCodeRepo.cacheTTL + const Duration(seconds: 1)),
          now,
        ),
        isFalse,
      );
      expect(
        SpaceCodeRepo.isFresh(writtenAgo(const Duration(days: 3)), now),
        isFalse,
      );
    });

    test('a missing stamp (pre-TTL cache entry) is stale', () {
      expect(SpaceCodeRepo.isFresh(null, now), isFalse);
    });
  });

  /// A ferry entry and its TTL stamp are two GetStorage keys, and a read that
  /// sees one without the other reads the entry as stale — and clears it. So
  /// the pair must become visible together: any read taken while a write is
  /// in flight must see the whole entry or none of it, never a value whose
  /// stamp has not landed yet.
  ///
  /// This is not theoretical. `GetStorage.write` applies the value to memory
  /// synchronously and then awaits a flush, so stamping only after awaiting
  /// the value write opens a real window — and on a native cold start the
  /// shell's DM-invite consumer mounts and reads inside it, destroying the
  /// invite the route had just cached. The link then did nothing until it was
  /// tapped a second time with the app already up (#8555).
  ///
  /// All three payloads (join code, activity id, DM invite) share the write,
  /// so the DM invite stands in for the set.
  group('SpaceCodeRepo — a read taken while a write is in flight', () {
    const invitedUser = '@william11:staging.pangea.chat';

    setUpAll(() async {
      final tempDir = await Directory.systemTemp.createTemp('space_code_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (methodCall) async => tempDir.path,
          );
      await GetStorage.init('class_storage');
    });

    setUp(() async {
      await SpaceCodeRepo.clearDmInviteUserId();
    });

    test('sees the whole entry, and leaves it intact', () async {
      final write = SpaceCodeRepo.setDmInviteUserId(invitedUser);

      // The consumer's read, landing between the entry and its stamp.
      expect(SpaceCodeRepo.dmInviteUserId, invitedUser);

      await write;
      // And the entry survived that read — a mid-write read must not be
      // mistaken for a stale entry and cleared.
      expect(SpaceCodeRepo.dmInviteUserId, invitedUser);
    });

    test('a clear leaves nothing readable behind', () async {
      await SpaceCodeRepo.setDmInviteUserId(invitedUser);

      final clear = SpaceCodeRepo.clearDmInviteUserId();
      expect(SpaceCodeRepo.dmInviteUserId, isNull);

      await clear;
      final storage = GetStorage('class_storage');
      expect(storage.read(PLocalKey.cachedDmInviteUserId), isNull);
      expect(storage.read(PLocalKey.cachedDmInviteUserIdAt), isNull);
    });
  });
}
