import 'package:fluffychat/features/navigation/room_id_url.dart';

/// Canonical route paths for Pangea-owned surfaces (world_v2).
///
/// world_v2 navigation is **token-driven**: internal navigation goes through the
/// `WorkspaceNav` token helpers (and the token locations/builders here —
/// [world], [chatsList], [course], [room], [worldObject]). The in-course
/// activity overlay is produced token-natively by
/// `WorkspaceNav.openCourseActivity` (#7267), not by a path builder here. The bare
/// **section-path** constants ([chats], [analytics], [courses], [settings],
/// [profile], [rooms]) are NOT navigation targets — they are legacy redirect
/// sources + `route_facts.sectionFor` identities that `LegacyRedirects` rewrites
/// to tokens before render. Never `context.go` a section path; see the
/// "Navigate by token, never by path" rule in `routing.instructions.md`.
/// Fork-owned Matrix rooms keep their upstream `/rooms/:roomid` shape so
/// push-notification and matrix.to deep-link handling stay untouched.
///
/// Design doc: `.github/vision/world_v2.md` (workspace root repo).
///
/// Room/space ids ride world_v2 URLs as bare localparts (the home server_name
/// is stripped here and re-attached on read — see room_id_url.dart).
abstract class PRoutes {
  /// World home — the app opens onto the map. World section root.
  static const String world = '/';

  /// Legacy chats section path. world_v2 has **no live `/chats` route** — the
  /// chat list is the `chats` left token over the world map ([chatsList]) — so
  /// the router redirects `/chats` (and the bare `/rooms` home) there. Kept only
  /// as the section's legacy-path identity (sibling to [analytics] / [settings],
  /// matched by `route_facts.sectionFor`); do NOT navigate to it. To open the
  /// chat list, use [chatsList].
  static const String chats = '/chats';

  /// The chat list as a live world_v2 location: the world map with the chats
  /// panel open (`/?left=chats`). The canonical "go to chats" target; [chats]
  /// and the bare `/rooms` legacy paths redirect here.
  static const String chatsList = '/?left=chats';

  /// Legacy analytics section path (redirect source / `sectionFor` identity, not
  /// a nav target). Analytics is token-driven: `right=analytics:<tab>` etc.
  static const String analytics = '/analytics';

  /// Legacy courses section path (redirect source / `sectionFor` identity). The
  /// bare hub is the `addcourse` left token; a joined course is [course]'s
  /// `?m=course:` filter. This base constant is not a direct nav target.
  static const String courses = '/courses';

  /// Legacy settings section path (redirect source / `sectionFor` identity, not a
  /// nav target). Settings is token-driven: `WorkspaceNav.openSettings`.
  static const String settings = '/settings';

  /// Legacy profile section path (formerly user_home; redirect source /
  /// `sectionFor` identity, not a nav target). Profile is the `settings` token.
  static const String profile = '/profile';

  /// Matrix rooms root — upstream-shaped on purpose. Bare `/rooms` redirects to
  /// [chatsList]; `/rooms/:roomid` is the deliberately-kept room shape ([room]).
  static const String rooms = '/rooms';

  // ---- builders -------------------------------------------------------

  /// One joined course (a Matrix space) — `/courses/:spaceid` (bare localpart).
  static String course(String spaceId) => '$courses/${shortRoomId(spaceId)}';

  /// A chat room — `/rooms/:roomid` (bare localpart).
  static String room(String roomId) => '$rooms/${shortRoomId(roomId)}';

  /// First-class world object (activity for now) — `/<uuid>`.
  static String worldObject(String id) => '/$id';

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
