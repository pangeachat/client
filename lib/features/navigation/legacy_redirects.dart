import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';

/// Folds externally produced activity, course-join, and Synapse email links
/// into workspace tokens before rendering. Retired internal routes are not
/// supported. [handle] also shortens home-server room ids in every location.
abstract class LegacyRedirects {
  static String? resolve(Uri uri) {
    // Path-strategy web routing retains the fragment on the root location.
    // Native app_links has already unwrapped it in incomingUriToPath.
    if (uri.path == '/' && uri.fragment.startsWith('/room/')) {
      return resolve(Uri.parse(uri.fragment));
    }
    final segments = uri.pathSegments;
    if ((segments.length == 2 || segments.length == 3) &&
        segments.first == 'room' &&
        segments[1].startsWith('!') &&
        segments[1].contains(':')) {
      return WorkspaceNav.openRoomById(
        Uri.parse(PRoutes.world),
        segments[1],
        event: segments.length == 3 ? segments[2] : null,
      );
    }
    if (segments.length != 1) return null;
    final segment = segments.first;
    if (PRoutes.isWorldObjectId(segment)) return _resolveActivityLink(uri);
    if (PRoutes.isJoinCode(segment)) return PRoutes.joinWithCode(segment);
    return null;
  }

  /// The `/<uuid>` shareable activity link → its `activity` token over the
  /// world map, the link's optional `launch=`/`roomid=`/`autoplay=` params
  /// riding the token's fields ([ActivityToken]). Any prior panels/context
  /// are dropped — this link IS the activity. Idempotent: the result has no
  /// UUID path segment, so it never re-fires.
  static String _resolveActivityLink(Uri uri) {
    final kept = WorkspaceQuery.parts(uri.query);
    final activityId = uri.pathSegments.first;
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
    final parts = [
      'left=${ActivityPanelToken(activityTokenParam).encode()}',
      ...kept,
    ];
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
