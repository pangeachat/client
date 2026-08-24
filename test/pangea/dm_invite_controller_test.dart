import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/dm_invite/dm_invite_controller.dart';

/// The DM invite landing can be entered more than once for the same link
/// before its open completes (a competing boot-time navigation remounts it;
/// the `/` auth guard re-enters it from the login-bounce ferry, #8436). Every
/// entry must await the ONE in-flight open — a second `createRoom` would be a
/// duplicate DM — and a completed open, success or failure, must release the
/// entry so a later click opens afresh.
void main() {
  group('DmInviteController.dedupeInFlight', () {
    test('concurrent opens for one user share a single open', () async {
      var opens = 0;
      final completer = Completer<String>();
      Future<String> open() {
        opens++;
        return completer.future;
      }

      final first = DmInviteController.dedupeInFlight('@a:x', open);
      final second = DmInviteController.dedupeInFlight('@a:x', open);
      expect(opens, 1);

      completer.complete('!room:x');
      expect(await first, '!room:x');
      expect(await second, '!room:x');
    });

    test('different users open independently', () async {
      var opens = 0;
      Future<String> open() async => '!room${++opens}:x';

      final a = DmInviteController.dedupeInFlight('@a:x', open);
      final b = DmInviteController.dedupeInFlight('@b:x', open);
      expect(await a, isNot(await b));
      expect(opens, 2);
    });

    test(
      'a completed open is released — the next click opens afresh',
      () async {
        var opens = 0;
        Future<String> open() async => '!room${++opens}:x';

        expect(
          await DmInviteController.dedupeInFlight('@a:x', open),
          '!room1:x',
        );
        expect(
          await DmInviteController.dedupeInFlight('@a:x', open),
          '!room2:x',
        );
      },
    );

    test('a failed open is released too, and the error reaches every '
        'awaiter', () async {
      var opens = 0;
      final completer = Completer<String>();
      Future<String> failing() {
        opens++;
        return completer.future;
      }

      final first = DmInviteController.dedupeInFlight('@a:x', failing);
      final second = DmInviteController.dedupeInFlight('@a:x', failing);
      completer.completeError(StateError('invalid user id'));
      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      expect(opens, 1);

      Future<String> open() async => '!room:x';
      expect(await DmInviteController.dedupeInFlight('@a:x', open), '!room:x');
    });
  });
}
