import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';

/// The cached-join-code TTL (#7524): an inbound join link's code is ferried
/// through GetStorage across the login bounce, so an entry cached long ago
/// (a visitor who never logged in, or an onboarding that never finished) must
/// not surprise-join a later login, possibly by a different account on a
/// shared browser. [SpaceCodeRepo.spaceCode] applies [SpaceCodeRepo.isFresh]
/// to the stored write stamp and clears stale entries on read; the boundary
/// logic is pinned here.
void main() {
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
}
