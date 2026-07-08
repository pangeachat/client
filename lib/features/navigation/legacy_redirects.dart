import 'package:fluffychat/features/navigation/activity_token.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';

/// The client's inbound URL rewrites. The client is the only producer of
/// its URLs (routing.instructions.md): retired shapes from earlier releases
/// are deleted, not redirected. What remains are the URL artifacts that live
/// outside the app — the shareable standalone activity link `/<uuid>` and the
/// course join link `/join_with_link?classcode=<code>` — folded into their
/// canonical tokens before anything renders. Wired as the router's single
/// top-level redirect; pure and synchronous. [handle] also display-shortens
/// home-server room ids on every location.
abstract class LegacyRedirects {
  /// The two spellings of the inbound course join link: `join_with_link` is
  /// the CloudFront viewer-request 302 target for a bare short code pasted at
  /// app.{staging.,}pangea.chat (share_room_code_util.dart, devops#105);
  /// `join` is the native app-link shape the incoming-URI listener emits for
  /// the same code (matrix.dart). Both carry the code as `?classcode=`.
  static const Set<String> _joinLinkPaths = {'join_with_link', 'join'};

  static String? resolve(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 1) return null;
    if (_joinLinkPaths.contains(segments.first)) return _resolveJoinLink(uri);
    if (!PRoutes.isWorldObjectId(segments.first)) return null;
    return _resolveActivityLink(uri);
  }

  /// The `/<uuid>` shareable activity link → its `activity` token over the
  /// world map, the link's optional `launch=`/`roomid=`/`autoplay=` params
  /// riding the token's fields ([ActivityToken]). Any prior panels/context
  /// are dropped — this link IS the activity. Idempotent: the result has no
  /// UUID path segment, so it never re-fires.
  static String _resolveActivityLink(Uri uri) {
    final kept = WorkspaceQuery.parts(uri.query);
    final token = PanelToken(
      'activity',
      ActivityToken.build(
        uri.pathSegments.first,
        roomId: WorkspaceQuery.valueOf(uri.query, 'roomid'),
        launch: WorkspaceQuery.valueOf(uri.query, 'launch') == 'true',
        autoplay: int.tryParse(
          WorkspaceQuery.valueOf(uri.query, 'autoplay') ?? '',
        ),
      ),
    );
    WorkspaceQuery.removeKeys(kept, {
      'left',
      'c',
      'activity',
      'roomid',
      'launch',
      'autoplay',
    });
    final parts = ['left=${token.encode()}', ...kept];
    return '${PRoutes.world}?${parts.join('&')}';
  }

  /// The course join link → the add-course panel's join-with-code leaf
  /// (`left=addcourse:private/<code>`), which performs the SAME join the
  /// manual join-with-code page does (#7524). Prior panels/context are
  /// dropped — this link IS the join. A missing, empty, or undecodable code
  /// degrades to the manual join-with-code page instead of a blank screen.
  /// Idempotent: the result has no join path segment, so it never re-fires.
  /// Logged out, the `/` auth guard ferries the code across the login bounce
  /// (see PAuthGaurd.roomsRedirect).
  static String _resolveJoinLink(Uri uri) {
    String? code;
    try {
      code = uri.queryParameters[SpaceConstants.classCode]?.trim();
    } catch (_) {
      // A hand-edited/truncated `%` escape must not crash route resolution;
      // degrade to the manual entry page.
      code = null;
    }
    if (code == null || code.isEmpty) {
      return '${PRoutes.world}?left=${const PanelToken('addcourse', 'private').encode()}';
    }
    return PRoutes.joinWithCode(code);
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
