import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';

/// User ids ride the invite-link URL as bare localparts (`@abc`) instead of
/// the full Matrix id (`@abc:home.server`), mirroring [shortRoomId]/
/// [fullRoomId] for room ids. The home server_name is assumed when absent and
/// re-attached before the id is used to start a DM. Federation-safe: ids from
/// another homeserver always carry their own `:domain`, so they are never
/// shortened and never get the home domain attached.
///
/// [shortUserId] is used where the invite link is built (`fluffy_share.dart`);
/// [dmInviteUserIdFor] where the link is read back (the invite route's
/// redirect, PAuthGaurd.dmInviteRedirect).

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

/// The in-app path of the DM invite route for [userId] —
/// `/invite_user/<localpart>`, the path half of [inviteLinkForUser]. [domain]
/// overrides the home domain (for tests).
String dmInvitePath(String userId, {String? domain}) =>
    '${PRoutes.dmInvite}/'
    '${Uri.encodeComponent(shortUserId(userId, domain: domain))}';

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
    '$frontendURL${dmInvitePath(userId, domain: domain)}';

/// Read a once-decoded `/invite_user/:userID` segment into the full mxid to
/// open a DM with. The router (and `Uri.pathSegments`) percent-decode a
/// segment once, but a shared link can reach us encoded twice — the share
/// text encodes the id, and a chat client that linkifies the message can
/// encode it again — which leaves the id still encoded after that first decode
/// and reads to the homeserver as an invalid mxid. Decode the leftover layer
/// when one is present, keeping the value as given if it isn't valid
/// percent-encoding, so a malformed link reaches the normal invalid-id message
/// instead of throwing out of the redirect. [domain] overrides the home domain
/// (for tests).
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

/// The invited user id a location addresses — the mxid when [uri] is a DM
/// invite link (`/invite_user/<id>`), else null. `Uri.pathSegments`
/// percent-decodes a segment once, exactly as the router decodes a path param,
/// so this reads the same link to the same id as a route builder would
/// (pinned in invite_user_link_test.dart). Read by the invite route's redirect
/// to cache the invite (PAuthGaurd.dmInviteRedirect). Logged out, the home
/// domain is unknown, so a bare-localpart link reads back bare and is cached
/// that way; the consumer re-attaches the domain post-login
/// (DmInviteController.pendingInviteUserId). [domain] overrides the home
/// domain (for tests).
String? dmInviteUserIdFor(Uri uri, {String? domain}) {
  final segments = uri.pathSegments;
  if (segments.length != 2 || '/${segments.first}' != PRoutes.dmInvite) {
    return null;
  }
  return userIdFromUrlParam(segments.last, domain: domain);
}
