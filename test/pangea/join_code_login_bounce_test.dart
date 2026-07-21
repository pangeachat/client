import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

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
}
