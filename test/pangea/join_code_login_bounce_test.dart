import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/user_id_url.dart';
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

  // A DM invite link (`/invite_user/<id>`) rides the same ferry (#8436):
  // cached across the bounce, re-entered on the logged-in landing, consumed
  // only by the invite landing once the DM has actually opened
  // (DmInviteLandingPage) — so a link click lands IN the DM instead of
  // waiting for the user to open the chat list.
  group('PAuthGaurd.consumeCachedJoinCode — DM invite links', () {
    const invitedUser = '@william11:staging.pangea.chat';
    final world = Uri.parse('/');

    setUp(() async {
      await SpaceCodeRepo.clearActivityId();
      await SpaceCodeRepo.clearDmInviteUserId();
    });

    test(
      'a fresh cached invite re-enters its landing route, cache kept',
      () async {
        await SpaceCodeRepo.setDmInviteUserId(invitedUser);

        final redirect = await PAuthGaurd.consumeCachedJoinCode(world);
        expect(redirect, isNotNull);
        expect(dmInviteUserIdFor(Uri.parse(redirect!)), invitedUser);
        // The cache survives the redirect: a landing disposed mid-open
        // retries on the next logged-in landing.
        expect(SpaceCodeRepo.dmInviteUserId, invitedUser);
        // Landing on the redirected-to URL stays put (the landing consumes).
        expect(
          await PAuthGaurd.consumeCachedJoinCode(Uri.parse(redirect)),
          isNull,
        );
        expect(SpaceCodeRepo.dmInviteUserId, invitedUser);
      },
    );

    test('every landing on `/` — including token URLs — re-enters until the '
        'landing consumes', () async {
      await SpaceCodeRepo.setDmInviteUserId(invitedUser);
      final chats = Uri.parse('/?left=chats');

      expect(await PAuthGaurd.consumeCachedJoinCode(chats), isNotNull);
      // The landing opening the DM is what consumes.
      await SpaceCodeRepo.clearDmInviteUserId();
      expect(await PAuthGaurd.consumeCachedJoinCode(chats), isNull);
    });

    test('any invite landing stays put, even for a different user — the '
        'clicked link is the fresher intent', () async {
      await SpaceCodeRepo.setDmInviteUserId(invitedUser);
      final other = Uri.parse(dmInvitePath('@other:staging.pangea.chat'));

      expect(await PAuthGaurd.consumeCachedJoinCode(other), isNull);
    });

    test('a pending join code or activity outranks a cached invite', () async {
      const uuid = 'a1aed3f6-1ef7-4ed0-bc46-4a393aaf880b';
      await SpaceCodeRepo.setDmInviteUserId(invitedUser);
      await SpaceCodeRepo.setActivityId(uuid);

      var redirect = await PAuthGaurd.consumeCachedJoinCode(world);
      expect(redirect, contains(uuid));
      expect(dmInviteUserIdFor(Uri.parse(redirect!)), isNull);

      await SpaceCodeRepo.setSpaceCode('vj3pc8b');
      redirect = await PAuthGaurd.consumeCachedJoinCode(world);
      expect(redirect, contains('vj3pc8b'));
      expect(dmInviteUserIdFor(Uri.parse(redirect!)), isNull);
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

        expect(await PAuthGaurd.consumeCachedJoinCode(world), isNull);
        expect(storage.read(PLocalKey.cachedDmInviteUserId), isNull);
      },
    );
  });
}
