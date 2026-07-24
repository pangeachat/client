import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/user_id_url.dart';

/// shortUserId/fullUserId mirror shortRoomId/fullRoomId (room_id_url.dart):
/// the invite link carries a bare localpart when the id is on the home
/// server, and the full id (untouched) when it isn't.
void main() {
  const domain = 'staging.pangea.chat';

  group('shortUserId', () {
    test('drops the home server_name', () {
      expect(shortUserId('@william11:$domain', domain: domain), '@william11');
    });

    test('leaves a foreign-homeserver id untouched', () {
      expect(
        shortUserId('@will:matrix.org', domain: domain),
        '@will:matrix.org',
      );
    });
  });

  group('fullUserId', () {
    test('re-attaches the home server_name to a bare localpart', () {
      expect(fullUserId('@william11', domain: domain), '@william11:$domain');
    });

    test('leaves a segment that already carries a domain untouched', () {
      expect(
        fullUserId('@will:matrix.org', domain: domain),
        '@will:matrix.org',
      );
    });
  });

  test('short then full round-trips back to the original id', () {
    const id = '@william11:$domain';
    expect(fullUserId(shortUserId(id, domain: domain), domain: domain), id);
  });
}
