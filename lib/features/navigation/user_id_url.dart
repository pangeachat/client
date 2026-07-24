import 'package:fluffychat/features/navigation/room_id_url.dart';

/// User ids ride the invite-link URL as bare localparts (`@abc`) instead of
/// the full Matrix id (`@abc:home.server`), mirroring [shortRoomId]/
/// [fullRoomId] for room ids. The home server_name is assumed when absent and
/// re-attached before the id is used to start a DM. Federation-safe: ids from
/// another homeserver always carry their own `:domain`, so they are never
/// shortened and never get the home domain attached.
///
/// [shortUserId] is used where the invite link is built (`fluffy_share.dart`);
/// [fullUserId] where the URL's `userID` param is read back (routes.dart page
/// builder for `/invite_user/:userID`).

/// Drop the home server_name so an id can ride a URL as a bare localpart. Ids
/// from another homeserver, or any id whose domain isn't the home domain, are
/// returned unchanged (still federation-resolvable). [domain] overrides the
/// home domain (for tests).
String shortUserId(String id, {String? domain}) =>
    shortRoomId(id, domain: domain);

/// Re-attach the home server_name to a URL `userID` param. A segment that
/// already has a `:domain` (a foreign-homeserver id, or an untouched full id)
/// is returned unchanged. [domain] overrides the home domain (for tests).
String fullUserId(String segment, {String? domain}) =>
    fullRoomId(segment, domain: domain);
