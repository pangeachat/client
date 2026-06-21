import 'package:fluffychat/features/navigation/room_id_url.dart';

/// Canonical route paths for Pangea-owned surfaces (world_v2).
///
/// All navigation goes through these constants and builders — never
/// hardcode a path string at a callsite. Fork-owned surfaces (Matrix
/// rooms) intentionally keep their upstream `/rooms/:roomid` shape so
/// push-notification and matrix.to deep-link handling stay untouched.
///
/// Design doc: `.github/vision/world_v2.md` (workspace root repo).
///
/// Room/space ids ride world_v2 URLs as bare localparts (the home server_name
/// is stripped here and re-attached on read — see room_id_url.dart).
abstract class PRoutes {
  /// World home — the app opens onto the map. World section root.
  static const String world = '/';

  /// Chats section root — the chat list. The world map (`/`) and chats
  /// are distinct sections in world_v2.
  static const String chats = '/chats';

  /// Learning analytics section root.
  static const String analytics = '/analytics';

  /// Courses section root (find/browse). A specific joined course lives
  /// at [course].
  static const String courses = '/courses';

  /// Settings section root.
  static const String settings = '/settings';

  /// Profile section root (formerly user_home).
  static const String profile = '/profile';

  /// Matrix rooms root — upstream-shaped on purpose.
  static const String rooms = '/rooms';

  // ---- builders -------------------------------------------------------

  /// One joined course (a Matrix space) — `/courses/:spaceid` (bare localpart).
  static String course(String spaceId) => '$courses/${shortRoomId(spaceId)}';

  /// A chat room — `/rooms/:roomid` (bare localpart).
  static String room(String roomId) => '$rooms/${shortRoomId(roomId)}';

  /// First-class world object (activity for now) — `/<uuid>`.
  static String worldObject(String id) => '/$id';

  /// Open an activity in its course — the canonical in-course overlay over the
  /// persistent map (`/courses/:spaceid?activity=:id`). [tab] preserves the
  /// underlying course tab, [roomId] joins an existing session room, [launch]
  /// skips the lobby. This is the single producer of the in-course open shape.
  static String activity(
    String spaceId,
    String activityId, {
    String? roomId,
    bool launch = false,
    String? tab,
  }) {
    final params = <String>['activity=$activityId'];
    if (tab != null) params.add('tab=$tab');
    if (roomId != null) params.add('roomid=${shortRoomId(roomId)}');
    if (launch) params.add('launch=true');
    return '${course(spaceId)}?${params.join('&')}';
  }

  /// Open an activity with no course context — the shareable first-class uuid
  /// (`/<uuid>`). [launch] skips the lobby.
  static String activityStandalone(String activityId, {bool launch = false}) =>
      launch
      ? '${worldObject(activityId)}?launch=true'
      : worldObject(activityId);

  /// Inline go_router parameter regex used by first-class world-object
  /// routes so they can never shadow literal routes like [analytics].
  static const String uuidPattern =
      '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      '[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

  static final RegExp _uuidRegExp = RegExp('^$uuidPattern\$');

  /// Whether [segment] is a world-object id rather than a literal route.
  static bool isWorldObjectId(String segment) => _uuidRegExp.hasMatch(segment);
}
