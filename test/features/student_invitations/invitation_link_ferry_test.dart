import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';

/// The seat invitation link `<app>/<class code>?inv=<id>` (SPEC §4 Student 2,
/// V4): the class code still joins as before, and the invitation id rides
/// the fold into its own ferry entry, so it survives the login bounce into
/// sign-up/sign-in and is confirmed after sign-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('inv_ferry_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('class_storage');
  });

  setUp(() async {
    await SpaceCodeRepo.clearDestination();
    await SpaceCodeRepo.clearPendingInvitation();
  });

  const code = 'vj3pc8b';
  const inv = 'Q2xhc3NJbnZpdGUtMDAx_-';

  group('join link fold keeps inv', () {
    test('the folded join location carries the invitation id', () {
      final out = LegacyRedirects.resolve(Uri.parse('/$code?inv=$inv'));
      expect(out, PRoutes.joinWithCode(code, invitationId: inv));
      final uri = Uri.parse(out!);
      expect(joinCodeFor(uri), code, reason: 'the class code still joins');
      expect(PRoutes.invitationIdIn(uri), inv);
    });

    test('other link params are still dropped', () {
      final out = LegacyRedirects.resolve(
        Uri.parse('/$code?left=chats&inv=$inv&c=abc'),
      );
      expect(out, PRoutes.joinWithCode(code, invitationId: inv));
    });

    test('a link without inv folds exactly as before', () {
      expect(
        LegacyRedirects.resolve(Uri.parse('/$code')),
        PRoutes.joinWithCode(code),
      );
      expect(PRoutes.joinWithCode(code), isNot(contains('inv=')));
    });

    test('a malformed inv is dropped, never carried', () {
      for (final bad in ['', 'a b', 'x' * 65, '<script>', 'a%2Fb']) {
        final out = LegacyRedirects.resolve(
          Uri.parse('/$code?inv=${Uri.encodeQueryComponent(bad)}'),
        );
        expect(out, PRoutes.joinWithCode(code), reason: bad);
      }
    });
  });

  group('inv survives login bounce', () {
    test('the guard moves inv into its own ferry entry and strips the URL, '
        'so the bounce keeps the join and the invitation both', () async {
      final folded = Uri.parse(PRoutes.joinWithCode(code, invitationId: inv));
      final stripped = await PAuthGaurd.stashInvitation(folded);
      expect(stripped, PRoutes.joinWithCode(code));
      expect(SpaceCodeRepo.pendingInvitation?.invitationId, inv);

      // The bounce caches the stripped location (no id in the stored URL).
      final destination = PAuthGaurd.bounceDestinationFor(Uri.parse(stripped!));
      expect(destination, PRoutes.joinWithCode(code));
      await SpaceCodeRepo.setDestination(destination!);

      // The sign-up/sign-in screens read both after the bounce.
      expect(SpaceCodeRepo.pendingJoinCode, code);
      expect(SpaceCodeRepo.pendingInvitation?.invitationId, inv);
      expect(SpaceCodeRepo.pendingInvitation?.ackedDisclosureVersion, isNull);
    });

    testWidgets('the `/` guard stashes before anything else, logged in or '
        'out', (tester) async {
      late BuildContext captured;
      late GoRouterState state;
      final router = GoRouter(
        initialLocation: PRoutes.joinWithCode(code, invitationId: inv),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, s) {
              captured = context;
              state = s;
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      // No Matrix above this context: the guard must answer from the stash
      // alone, before it reads any login state.
      final redirect = await tester.runAsync(
        () async => PAuthGaurd.roomsRedirect(captured, state),
      );
      expect(redirect, PRoutes.joinWithCode(code));
      expect(SpaceCodeRepo.pendingInvitation?.invitationId, inv);
    });

    test('a location without inv is left to the guard as is', () async {
      expect(
        await PAuthGaurd.stashInvitation(Uri.parse(PRoutes.joinWithCode(code))),
        isNull,
      );
      expect(SpaceCodeRepo.pendingInvitation, isNull);
    });

    test('landing again on the same invitation keeps the ticked checkbox; '
        'a different invitation replaces it', () async {
      await SpaceCodeRepo.setPendingInvitation(
        const PendingInvitation(inv, ackedDisclosureVersion: 2),
      );
      final again = Uri.parse(PRoutes.joinWithCode(code, invitationId: inv));
      await PAuthGaurd.stashInvitation(again);
      expect(SpaceCodeRepo.pendingInvitation?.ackedDisclosureVersion, 2);

      const other = 'b3RoZXJJbnZpdGF0aW9u';
      await PAuthGaurd.stashInvitation(
        Uri.parse(PRoutes.joinWithCode(code, invitationId: other)),
      );
      expect(SpaceCodeRepo.pendingInvitation?.invitationId, other);
      expect(SpaceCodeRepo.pendingInvitation?.ackedDisclosureVersion, isNull);
    });

    test('a stale invitation entry reads as absent', () async {
      await SpaceCodeRepo.setPendingInvitation(const PendingInvitation(inv));
      final storage = GetStorage('class_storage');
      await storage.write(
        PLocalKey.cachedInvitationAt,
        DateTime.now()
            .subtract(SpaceCodeRepo.cacheTTL + const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      expect(SpaceCodeRepo.pendingInvitation, isNull);
    });
  });
}
