/// Canonical route paths for Pangea-owned surfaces (world_v2).
///
/// All navigation goes through these constants and builders — never
/// hardcode a path string at a callsite. Fork-owned surfaces (Matrix
/// rooms) intentionally keep their upstream `/rooms/:roomid` shape so
/// push-notification and matrix.to deep-link handling stay untouched.
///
/// Design doc: `.github/vision/world_v2.md` (workspace root repo).
abstract class PRoutes {
  /// World home — the app opens onto the map. Chats section root.
  static const String world = '/';

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

  /// One joined course (a Matrix space) — `/courses/:spaceid`.
  static String course(String spaceId) => '$courses/$spaceId';

  /// A chat room — `/rooms/:roomid`.
  static String room(String roomId) => '$rooms/$roomId';

  /// First-class world object (activity for now) — `/<uuid>`.
  static String worldObject(String id) => '/$id';

  /// Inline go_router parameter regex used by first-class world-object
  /// routes so they can never shadow literal routes like [analytics].
  static const String uuidPattern =
      '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      '[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

  static final RegExp _uuidRegExp = RegExp('^$uuidPattern\$');

  /// Whether [segment] is a world-object id rather than a literal route.
  static bool isWorldObjectId(String segment) =>
      _uuidRegExp.hasMatch(segment);
}
