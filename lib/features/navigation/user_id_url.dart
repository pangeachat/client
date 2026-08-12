import 'package:fluffychat/features/navigation/room_id_url.dart';

/// User ids ride the invite-link URL as bare localparts (`@abc`) instead of
/// the full Matrix id (`@abc:home.server`), mirroring [shortRoomId]/
/// [fullRoomId] for room ids. The home server_name is assumed when absent and
/// re-attached before the id is used to start a DM. Federation-safe: ids from
/// another homeserver always carry their own `:domain`, so they are never
/// shortened and never get the home domain attached.
///
/// [shortUserId] is used where the invite link is built (`fluffy_share.dart`);
/// [userIdFromUrlParam] where the URL's `userID` param is read back
/// (routes.dart page builder for `/invite_user/:userID`).

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

/// The "Share invite link" URL that opens a DM with [userId].
///
/// A path, **not** a `/#/` link. Web runs under `usePathUrlStrategy`, where a
/// fragment is not part of the route, so a hash link boots the app at `/` and
/// the invite route never fires. Only the native app_links path ever unwrapped
/// the fragment ([MatrixState.incomingUriToPath]), which is why a hash link
/// worked on iOS and did nothing at all on web. CloudFront serves the SPA shell
/// for every path, so a direct path load boots. [domain] overrides the home
/// domain (for tests).
String inviteLinkForUser(String frontendURL, String userId, {String? domain}) =>
    '$frontendURL/invite_user/'
    '${Uri.encodeComponent(shortUserId(userId, domain: domain))}';

/// Read the `/invite_user/:userID` path param into the full mxid to open a DM
/// with. The router percent-decodes a path param once on its own, but a shared
/// link can reach us encoded twice — the share text encodes the id, and a chat
/// client that linkifies the message can encode it again — which leaves the id
/// still encoded after that first decode and reads to the homeserver as an
/// invalid mxid. Decode the leftover layer when one is present, keeping the
/// value as given if it isn't valid percent-encoding, so a malformed link
/// reaches the normal invalid-id message instead of throwing out of the route
/// builder. [domain] overrides the home domain (for tests).
String userIdFromUrlParam(String param, {String? domain}) {
  var value = param;
  if (value.contains('%')) {
    try {
      value = Uri.decodeComponent(value);
    } on ArgumentError {
      // Not valid percent-encoding; treat it as a literal and let the id fail
      // validation downstream rather than breaking route creation.
    }
  }
  return fullUserId(value, domain: domain);
}
