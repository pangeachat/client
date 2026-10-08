import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/dm_invite/dm_invite_controller.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';

/// The login-bounce ferry (routing.instructions.md § A signed-out visitor's
/// destination): the workspace location a logged-out visitor opened is
/// cached by the `/` auth guard's bounce and re-entered by the same guard's
/// next logged-in landing, which clears it in the same step. One entry
/// carries every link kind — a settings page, a course room, the shareable
/// activity link, the course join link — because they are all workspace URLs
/// by the time the guard runs (#9283), and only a workspace location is ever
/// kept, so the bounce can never send anyone off the app. The DM invite link
/// keeps its own entry, read from inside the shell. The TTL boundary itself
/// is pinned in space_code_repo_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('login_bounce_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('class_storage');
  });

  final world = Uri.parse('/');
  const settings = '/?right=settings';
  const courseRoom = '/?c=abc&left=course,room:def';
  const uuid = 'a1aed3f6-1ef7-4ed0-bc46-4a393aaf880b';
  const activity = '/?left=activity:$uuid';
  final joinLink = PRoutes.joinWithCode('vj3pc8b');

  Future<void> writeRaw(String value, {Duration age = Duration.zero}) async {
    final storage = GetStorage('class_storage');
    await storage.write(PLocalKey.cachedDestination, value);
    await storage.write(
      PLocalKey.cachedDestinationAt,
      DateTime.now().subtract(age).millisecondsSinceEpoch,
    );
  }

  group('SpaceCodeRepo.isValidDestination', () {
    test('a workspace location is a destination', () {
      for (final location in [settings, courseRoom, activity, joinLink]) {
        expect(
          SpaceCodeRepo.isValidDestination(location),
          isTrue,
          reason: location,
        );
      }
    });

    test('the bare world root is not — there is nothing to keep', () {
      expect(SpaceCodeRepo.isValidDestination('/'), isFalse);
      expect(SpaceCodeRepo.isValidDestination('/?'), isFalse);
    });

    test('no other path, and never an absolute URL', () {
      for (final location in [
        '/home/login',
        '/invite_user/@will',
        '/onboarding',
        'https://evil.example/?left=chats',
        '//evil.example/?left=chats',
        'javascript:alert(1)',
        '',
      ]) {
        expect(
          SpaceCodeRepo.isValidDestination(location),
          isFalse,
          reason: location,
        );
      }
    });
  });

  group('PAuthGaurd.bounceDestinationFor', () {
    test('keeps the workspace location the visitor opened', () {
      expect(PAuthGaurd.bounceDestinationFor(Uri.parse(settings)), settings);
      expect(PAuthGaurd.bounceDestinationFor(Uri.parse(joinLink)), joinLink);
    });

    test('keeps nothing for the bare root — a plain open or the native SSO '
        'callback must not overwrite a real destination', () {
      expect(PAuthGaurd.bounceDestinationFor(world), isNull);
    });

    test('keeps nothing for the DM invite route, which has its own entry', () {
      expect(
        PAuthGaurd.bounceDestinationFor(Uri.parse('/invite_user/@will')),
        isNull,
      );
    });
  });

  group('PAuthGaurd.consumeCachedDestination', () {
    setUp(() async {
      await SpaceCodeRepo.clearDestination();
    });

    test('a fresh destination redirects the landing there and is cleared in '
        'the same step', () async {
      await SpaceCodeRepo.setDestination(settings);

      expect(await PAuthGaurd.consumeCachedDestination(world), settings);
      expect(SpaceCodeRepo.destination, isNull);
      // The redirected-to landing, and every later one, finds nothing: a
      // later login never replays it, and the shell may rewrite the landing
      // URL without re-triggering it.
      expect(
        await PAuthGaurd.consumeCachedDestination(Uri.parse(settings)),
        isNull,
      );
      expect(await PAuthGaurd.consumeCachedDestination(world), isNull);
    });

    test('every link kind rides the same entry, whole workspace context '
        'included', () async {
      for (final location in [courseRoom, activity, joinLink]) {
        await SpaceCodeRepo.setDestination(location);
        expect(await PAuthGaurd.consumeCachedDestination(world), location);
      }
    });

    test('the last link opened before signing in wins', () async {
      await SpaceCodeRepo.setDestination(joinLink);
      await SpaceCodeRepo.setDestination(activity);

      expect(await PAuthGaurd.consumeCachedDestination(world), activity);
      expect(await PAuthGaurd.consumeCachedDestination(world), isNull);
    });

    test(
      'a landing already on the destination stays put and clears it',
      () async {
        await SpaceCodeRepo.setDestination(settings);

        expect(
          await PAuthGaurd.consumeCachedDestination(Uri.parse(settings)),
          isNull,
        );
        expect(SpaceCodeRepo.destination, isNull);
      },
    );

    test('nothing cached means no redirect', () async {
      expect(await PAuthGaurd.consumeCachedDestination(world), isNull);
    });

    test('a stale destination (past the TTL) is ignored and cleared', () async {
      await writeRaw(
        settings,
        age: SpaceCodeRepo.cacheTTL + const Duration(minutes: 1),
      );

      expect(await PAuthGaurd.consumeCachedDestination(world), isNull);
      expect(
        GetStorage('class_storage').read(PLocalKey.cachedDestination),
        isNull,
      );
    });

    test('a stored value that is not a workspace location is refused and '
        'cleared — the bounce can never send anyone off the app', () async {
      for (final value in ['https://evil.example/?left=chats', '/', '/home']) {
        await writeRaw(value);

        expect(await PAuthGaurd.consumeCachedDestination(world), isNull);
        expect(
          GetStorage('class_storage').read(PLocalKey.cachedDestination),
          isNull,
          reason: value,
        );
      }
    });

    test('onboarding reads a join code out of a join-link destination, and '
        'nothing out of any other', () {
      expect(joinCodeFor(Uri.parse(joinLink)), 'vj3pc8b');
      for (final location in [settings, courseRoom, activity]) {
        expect(joinCodeFor(Uri.parse(location)), isNull, reason: location);
      }
    });
  });

  // The DM invite link (`/invite_user/<id>`) keeps its own entry (#8436): the
  // invite route's redirect caches the id, on every landing, and the shell
  // itself opens the DM (DmInviteFerryConsumer → DmInviteController) —
  // the guard has no DM arm. Pinned here: the consumer's read of that entry,
  // the domain re-attach, waiting behind a coded join, and the TTL.
  group('DM invite links — the shell-side read of their own entry', () {
    const domain = 'staging.pangea.chat';
    const invitedUser = '@william11:$domain';

    setUp(() async {
      await SpaceCodeRepo.clearDestination();
      await SpaceCodeRepo.clearDmInviteUserId();
    });

    test('the guard does not redirect for a pending invite — the shell '
        'consumes it wherever the user lands', () async {
      await SpaceCodeRepo.setDmInviteUserId(invitedUser);

      expect(await PAuthGaurd.consumeCachedDestination(world), isNull);
      // And the read is a read: the entry survives until the DM opens.
      expect(SpaceCodeRepo.dmInviteUserId, invitedUser);
    });

    test('a fresh cached invite is pending, with the home domain '
        're-attached to a bare localpart cached pre-login', () async {
      await SpaceCodeRepo.setDmInviteUserId('@william11');
      expect(
        DmInviteController.pendingInviteUserId(world, domain: domain),
        invitedUser,
      );

      await SpaceCodeRepo.setDmInviteUserId('@will:matrix.org');
      expect(
        DmInviteController.pendingInviteUserId(world, domain: domain),
        '@will:matrix.org',
      );
    });

    test('nothing cached means nothing pending', () {
      expect(
        DmInviteController.pendingInviteUserId(world, domain: domain),
        isNull,
      );
    });

    test('the invite waits while a coded join is in progress on screen, and '
        'takes its turn on the next workspace navigation', () async {
      await SpaceCodeRepo.setDmInviteUserId(invitedUser);

      expect(
        DmInviteController.pendingInviteUserId(
          Uri.parse(joinLink),
          domain: domain,
        ),
        isNull,
      );
      // The join landed on its course — or anywhere else — and the invite
      // is next; an open activity does not hold it back.
      for (final location in [courseRoom, activity, '/?left=chats']) {
        expect(
          DmInviteController.pendingInviteUserId(
            Uri.parse(location),
            domain: domain,
          ),
          invitedUser,
          reason: location,
        );
      }
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

        expect(
          DmInviteController.pendingInviteUserId(world, domain: domain),
          isNull,
        );
        expect(storage.read(PLocalKey.cachedDmInviteUserId), isNull);
      },
    );
  });
}
