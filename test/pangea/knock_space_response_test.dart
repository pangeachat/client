import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';

/// Unit coverage for the `/knock_with_code` response + error parsing (#7592):
/// the new `banned` field on mixed 200 outcomes, and the typed
/// banned-from-every-room exception derived from a 403 body.
void main() {
  group('KnockSpaceResponse.fromJson', () {
    test('parses rooms, already_joined, and banned', () {
      final response = KnockSpaceResponse.fromJson({
        'rooms': ['!a:server'],
        'already_joined': ['!b:server'],
        'banned': ['!c:server'],
      });
      expect(response.roomIds, ['!a:server']);
      expect(response.alreadyJoined, ['!b:server']);
      expect(response.banned, ['!c:server']);
    });

    test('defaults banned to empty when the key is absent (back-compat)', () {
      final response = KnockSpaceResponse.fromJson({
        'rooms': ['!a:server'],
      });
      expect(response.banned, isEmpty);
      expect(response.roomIds, ['!a:server']);
    });

    test('round-trips banned through toJson', () {
      final response = KnockSpaceResponse(
        roomIds: const [],
        alreadyJoined: const [],
        banned: const ['!c:server'],
      );
      expect(response.toJson()['banned'], ['!c:server']);
    });
  });

  group('BannedFromRoomException.fromErrorBody', () {
    test('returns a typed exception with the banned list on the ban errcode', () {
      final exception = BannedFromRoomException.fromErrorBody(
        jsonEncode({
          'errcode': 'ORG.PANGEA.BANNED_FROM_ROOM',
          'error': 'You are banned from every matched room.',
          'banned': ['!room:server'],
        }),
      );
      expect(exception, isNotNull);
      expect(exception!.banned, ['!room:server']);
    });

    test('tolerates a missing banned list', () {
      final exception = BannedFromRoomException.fromErrorBody(
        jsonEncode({'errcode': 'ORG.PANGEA.BANNED_FROM_ROOM'}),
      );
      expect(exception, isNotNull);
      expect(exception!.banned, isEmpty);
    });

    test('returns null for a different errcode', () {
      final exception = BannedFromRoomException.fromErrorBody(
        jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'nope'}),
      );
      expect(exception, isNull);
    });

    test('returns null (never throws) for a non-JSON body', () {
      expect(
        BannedFromRoomException.fromErrorBody('<html>502 Bad Gateway</html>'),
        isNull,
      );
    });
  });
}
