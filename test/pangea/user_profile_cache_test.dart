import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/user/user_profile_cache.dart';
import 'get_test_client.dart';

/// Covers #8192: participants of a session the learner has not joined rendered
/// as their localpart with the default letter avatar, because the name and
/// avatar were resolved upstream from room state that doesn't exist for such a
/// session. Cards now resolve a bare user id through this cache, which reads
/// the user's *global* profile — available with no room membership at all.
void main() {
  late Client client;

  // The SDK's profile lookup reads its sqflite cache before the network, and
  // that read hangs on an uninitialized ffi factory rather than failing.
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    UserProfileCache.reset();
    client = await getTestClient();
  });

  tearDown(() async {
    UserProfileCache.reset();
    await client.dispose();
  });

  const alice = '@alice:example.com';

  test('resolves a display name and avatar for a user the client shares no '
      'room with', () async {
    final profile = await UserProfileCache.fetch(client, alice);

    expect(profile.displayName, 'Alice M');
    expect(profile.avatarUrl, Uri.parse('mxc://test'));
  });

  test('a resolved profile is readable synchronously afterwards, so a card '
      'draws it within the frame instead of flashing the fallback', () async {
    expect(UserProfileCache.cached(alice), isNull);

    await UserProfileCache.fetch(client, alice);

    expect(UserProfileCache.cached(alice)?.displayName, 'Alice M');
  });

  test('an unresolvable profile is not remembered, so a later frame retries '
      'rather than pinning the user to the default name and avatar', () async {
    const unknown = '@nobody:example.com';

    final profile = await UserProfileCache.fetch(client, unknown);

    // The SDK swallows the lookup failure and hands back an empty profile;
    // caching that would be indistinguishable from the bug being fixed.
    expect(profile.displayName, isNull);
    expect(profile.avatarUrl, isNull);
    expect(UserProfileCache.cached(unknown), isNull);
  });

  test('a different client drops everything cached — a new login is a new '
      'server view of every profile', () async {
    await UserProfileCache.fetch(client, alice);
    expect(UserProfileCache.cached(alice), isNotNull);

    final other = await getTestClient();
    addTearDown(other.dispose);
    await UserProfileCache.fetch(other, '@nobody:example.com');

    expect(UserProfileCache.cached(alice), isNull);
  });
}
