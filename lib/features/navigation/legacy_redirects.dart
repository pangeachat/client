import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';

/// The client's ONE inbound URL rewrite. The client is the only producer of
/// its URLs (routing.instructions.md): retired shapes from earlier releases
/// are deleted, not redirected. What remains is the shareable standalone
/// activity link `/<uuid>` — the one URL artifact that lives outside the
/// app — folded into its canonical `left=activity:` token before anything
/// renders. Wired as the router's single top-level redirect; pure and
/// synchronous. [handle] also display-shortens home-server room ids on every
/// location.
abstract class LegacyRedirects {
  /// The `/<uuid>` shareable activity link → its `activity` token over the
  /// world map, the link's optional `launch=`/`roomid=`/`autoplay=` params
  /// riding the token's fields ([ActivityTokenParam]). Any prior panels/context
  /// are dropped — this link IS the activity. Idempotent: the result has no
  /// UUID path segment, so it never re-fires. Returns null for every other
  /// location.
  static String? resolve(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 1 || !PRoutes.isWorldObjectId(segments.first)) {
      return null;
    }
    final kept = WorkspaceQuery.parts(uri.query);
    final activityId = segments.first;
    final roomId = WorkspaceQuery.valueOf(uri.query, 'roomid');
    final launch = WorkspaceQuery.valueOf(uri.query, 'launch') == 'true';
    final autoplay = int.tryParse(
      WorkspaceQuery.valueOf(uri.query, 'autoplay') ?? '',
    );
    final activityTokenParam = ActivityTokenParam(
      activityId: activityId,
      roomId: roomId,
      launch: launch,
      autoplay: autoplay,
    );

    WorkspaceQuery.removeKeys(kept, {
      'left',
      'c',
      'activity',
      'roomid',
      'launch',
      'autoplay',
    });
    final parts = ['left=${activityTokenParam.token.encode()}', ...kept];
    return '${PRoutes.world}?${parts.join('&')}';
  }

  /// go_router top-level redirect adapter: apply [resolve], then shorten home
  /// room ids so URLs display as bare localparts (the read side re-attaches
  /// the domain — see room_id_url.dart). Never redirects to the location the
  /// router is already at.
  static String? handle(Uri uri) {
    final candidate = resolve(uri) ?? uri.toString();
    final shortened = shortenHomeRoomIdsInUrl(candidate);
    return shortened == uri.toString() ? null : shortened;
  }
}
