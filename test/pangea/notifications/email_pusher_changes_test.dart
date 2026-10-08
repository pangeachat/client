import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/notifications/email_pusher_changes.dart';

void main() {
  final phonePusher = Pusher(
    kind: 'http',
    pushkey: 'device-token',
    appId: 'com.talktolearn.chat',
    appDisplayName: 'Pangea Chat',
    deviceDisplayName: 'Phone',
    lang: 'en',
    data: PusherData(),
  );

  group('EmailPusherChanges', () {
    test('adds a pusher for each address that has none', () {
      final changes = EmailPusherChanges.toMatch(
        emailsEnabled: true,
        addresses: {'a@example.com', 'b@example.com'},
        pushers: [EmailPusherChanges.pusherFor('a@example.com'), phonePusher],
      );

      expect(changes.addressesToAdd, {'b@example.com'});
      expect(changes.pushersToRemove, isEmpty);
    });

    test('removes every email pusher and leaves device pushers', () {
      final changes = EmailPusherChanges.toMatch(
        emailsEnabled: false,
        addresses: {'a@example.com'},
        pushers: [EmailPusherChanges.pusherFor('a@example.com'), phonePusher],
      );

      expect(changes.addressesToAdd, isEmpty);
      expect(changes.pushersToRemove.map((id) => id.toJson()), [
        {'app_id': 'm.email', 'pushkey': 'a@example.com'},
      ]);
    });

    test('changes nothing when the pushers already match', () {
      final changes = EmailPusherChanges.toMatch(
        emailsEnabled: true,
        addresses: {'a@example.com'},
        pushers: [EmailPusherChanges.pusherFor('a@example.com')],
      );

      expect(changes.addressesToAdd, isEmpty);
      expect(changes.pushersToRemove, isEmpty);
    });

    test('adds nothing for an account with no email address', () {
      final changes = EmailPusherChanges.toMatch(
        emailsEnabled: true,
        addresses: {},
        pushers: [phonePusher],
      );

      expect(changes.addressesToAdd, isEmpty);
      expect(changes.pushersToRemove, isEmpty);
    });
  });
}
