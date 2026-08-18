import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/dm_invite/dm_invite_controller.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';

/// The consumption half of the login-bounce join-code ferry: a logged-in
/// landing redirects into the join flow of a fresh cached code, and the
/// GUARD NEVER CLEARS the cache — only the join page's actually-firing
/// submit does (CourseCodePage). Redirecting lives in the auth guard because
/// it is the one place every login transport passes through — a web SSO
/// login returns via a full page reload and a restored session boots
/// straight to `/`, so a login-state listener never fires for them. Clearing
/// any earlier (on redirect, or on landing) lost the code whenever a
/// competing boot-time navigation preempted the next step; left uncleared,
/// every logged-in landing retries until a submit fires. The caching half is
/// PAuthGaurd's login bounce; the TTL boundary is pinned in
/// space_code_repo_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('join_bounce_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('class_storage');
  });

  setUp(() async {
    await SpaceCodeRepo.clearSpaceCode();
  });

  group('PAuthGaurd.consumeCachedJoinCode', () {
    final world = Uri.parse('/');
    final codedUrl = Uri.parse('/?left=addcoursepage:private.jvj3pc8b');

    test(
      'a fresh cached code redirects into its join flow, cache kept',
      () async {
        await SpaceCodeRepo.setSpaceCode('vj3pc8b');

        final redirect = await PAuthGaurd.consumeCachedJoinCode(world);
        expect(redirect, isNotNull);
        expect(redirect, contains('vj3pc8b'));
        // The cache survives the redirect: a preempted navigation retries on
        // the next logged-in landing instead of losing the code.
        expect(SpaceCodeRepo.spaceCode, 'vj3pc8b');
      },
    );

    test('landing on the coded URL stays put; the cache survives for the '
        'page submit to consume', () async {
      await SpaceCodeRepo.setSpaceCode('vj3pc8b');

      expect(await PAuthGaurd.consumeCachedJoinCode(codedUrl), isNull);
      expect(SpaceCodeRepo.spaceCode, 'vj3pc8b');
    });

    test(
      'a preempted landing retries until the submit clears the cache',
      () async {
        await SpaceCodeRepo.setSpaceCode('vj3pc8b');

        final redirect = await PAuthGaurd.consumeCachedJoinCode(world);
        expect(redirect, isNotNull);
        // The landing renders but a competing navigation returns to the world
        // before the submit fires: the guard redirects again.
        expect(
          await PAuthGaurd.consumeCachedJoinCode(Uri.parse(redirect!)),
          isNull,
        );
        expect(await PAuthGaurd.consumeCachedJoinCode(world), redirect);
        // The submit firing (CourseCodePage) is what consumes.
        await SpaceCodeRepo.clearSpaceCode();
        expect(await PAuthGaurd.consumeCachedJoinCode(world), isNull);
      },
    );

    test('no cached code means no redirect', () async {
      expect(await PAuthGaurd.consumeCachedJoinCode(world), isNull);
    });

    test('a stale cached code (past the TTL) is ignored and cleared', () async {
      final storage = GetStorage('class_storage');
      await storage.write(PLocalKey.cachedSpaceCodeToJoin, 'vj3pc8b');
      await storage.write(
        PLocalKey.cachedSpaceCodeToJoinAt,
        DateTime.now()
            .subtract(SpaceCodeRepo.cacheTTL + const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );

      expect(await PAuthGaurd.consumeCachedJoinCode(world), isNull);
      expect(storage.read(PLocalKey.cachedSpaceCodeToJoin), isNull);
    });
  });

  // A shared activity link (`/<uuid>`) rides the same ferry (#7821): cached
  // across the bounce, redirected on the logged-in landing, consumed only
  // when the activity panel opens (LeftPanelActivityDetailsSubpage).
  group('PAuthGaurd.consumeCachedJoinCode — activity links', () {
    const uuid = 'a1aed3f6-1ef7-4ed0-bc46-4a393aaf880b';
    final world = Uri.parse('/');

    setUp(() async {
      await SpaceCodeRepo.clearActivityId();
    });

    test(
      'a fresh cached activity redirects to its token URL, cache kept',
      () async {
        await SpaceCodeRepo.setActivityId(uuid);

        final redirect = await PAuthGaurd.consumeCachedJoinCode(world);
        expect(redirect, isNotNull);
        expect(redirect, contains(uuid));
        expect(SpaceCodeRepo.activityId, uuid);
        // Landing on the redirected-to URL stays put (the panel consumes).
        expect(
          await PAuthGaurd.consumeCachedJoinCode(Uri.parse(redirect!)),
          isNull,
        );
        expect(SpaceCodeRepo.activityId, uuid);
      },
    );

    test('a pending join code outranks a cached activity', () async {
      await SpaceCodeRepo.setSpaceCode('vj3pc8b');
      await SpaceCodeRepo.setActivityId(uuid);

      final redirect = await PAuthGaurd.consumeCachedJoinCode(world);
      expect(redirect, contains('vj3pc8b'));
      expect(redirect, isNot(contains(uuid)));
    });

    test(
      'a stale cached activity (past the TTL) is ignored and cleared',
      () async {
        final storage = GetStorage('class_storage');
        await storage.write(PLocalKey.cachedActivityToOpen, uuid);
        await storage.write(
          PLocalKey.cachedActivityToOpenAt,
          DateTime.now()
              .subtract(SpaceCodeRepo.cacheTTL + const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        );

        expect(await PAuthGaurd.consumeCachedJoinCode(world), isNull);
        expect(storage.read(PLocalKey.cachedActivityToOpen), isNull);
      },
    );
  });

  // A DM invite link (`/invite_user/<id>`) rides the same ferry (#8436), but
  // its consumer is the shell itself (DmInviteFerryConsumer →
  // DmInviteController.consumePending), not a redirected-to page: the invite
  // route's redirect caches the id and lands on the world map, and the guard
  // has no DM arm — so a landing with only an invite pending stays where it
  // is and the shell opens the DM over it. What is pinned here is the
  // consumer's read of the ferry: domain re-attach, precedence, TTL.
  group('DM invite links — the shell-side read of the ferry', () {
    const domain = 'staging.pangea.chat';
    const invitedUser = '@william11:$domain';
    final world = Uri.parse('/');

    setUp(() async {
      await SpaceCodeRepo.clearActivityId();
      await SpaceCodeRepo.clearDmInviteUserId();
    });

    test('the guard does not redirect for a pending invite — the shell '
        'consumes it wherever the user lands', () async {
      await SpaceCodeRepo.setDmInviteUserId(invitedUser);
      expect(await PAuthGaurd.consumeCachedJoinCode(world), isNull);
      expect(
        await PAuthGaurd.consumeCachedJoinCode(Uri.parse('/?left=chats')),
        isNull,
      );
      // And the read is a read: the ferry survives until the DM opens.
      expect(SpaceCodeRepo.dmInviteUserId, invitedUser);
    });

    test('a fresh cached invite is pending, with the home domain '
        're-attached to a bare localpart cached pre-login', () async {
      await SpaceCodeRepo.setDmInviteUserId('@william11');
      expect(
        DmInviteController.pendingInviteUserId(domain: domain),
        invitedUser,
      );

      await SpaceCodeRepo.setDmInviteUserId('@will:matrix.org');
      expect(
        DmInviteController.pendingInviteUserId(domain: domain),
        '@will:matrix.org',
      );
    });

    test('nothing cached means nothing pending', () {
      expect(DmInviteController.pendingInviteUserId(domain: domain), isNull);
    });

    test('a pending join code or activity outranks the invite, which waits '
        'its turn', () async {
      const uuid = 'a1aed3f6-1ef7-4ed0-bc46-4a393aaf880b';
      await SpaceCodeRepo.setDmInviteUserId(invitedUser);

      await SpaceCodeRepo.setActivityId(uuid);
      expect(DmInviteController.pendingInviteUserId(domain: domain), isNull);
      expect(await PAuthGaurd.consumeCachedJoinCode(world), contains(uuid));

      await SpaceCodeRepo.setSpaceCode('vj3pc8b');
      expect(DmInviteController.pendingInviteUserId(domain: domain), isNull);
      expect(
        await PAuthGaurd.consumeCachedJoinCode(world),
        contains('vj3pc8b'),
      );

      // Once both are consumed the invite is next.
      await SpaceCodeRepo.clearSpaceCode();
      await SpaceCodeRepo.clearActivityId();
      expect(
        DmInviteController.pendingInviteUserId(domain: domain),
        invitedUser,
      );
    });

    test(
      'a stale cached invite (past the TTL) is ignored and cleared',
      () async {
        final storage = GetStorage('class_storage');
        await storage.write(PLocalKey.cachedDmInviteUserId, invitedUser);
        await storage.write(
          PLocalKey.cachedDmInviteUserIdAt,
          DateTime.now()
              .subtract(SpaceCodeRepo.cacheTTL + const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        );

        expect(DmInviteController.pendingInviteUserId(domain: domain), isNull);
        expect(storage.read(PLocalKey.cachedDmInviteUserId), isNull);
      },
    );
  });
}
