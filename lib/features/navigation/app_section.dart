import 'package:flutter/material.dart';

import 'package:fluffychat/features/navigation/route_paths.dart';

/// The app's top-level sections — the single source of truth consumed by
/// the navigation rail (wide), the bottom nav bar (narrow), and the
/// left-column switcher. Selection is decided by exact first path
/// segment, never by substring matching on the full path.
///
/// The selected course space is navigation state too, but it is dynamic
/// (one entry per joined space on wide screens; a single switcher slot on
/// narrow screens), so it lives alongside — not inside — this enum:
/// a location under `/courses/:spaceid` means "a course is the active
/// section" and [AppSection.fromUri] returns [courses].
enum AppSection {
  /// World home + chats. Root: `/`.
  chats(
    rootPath: PRoutes.world,
    icon: Icons.forum_outlined,
    selectedIcon: Icons.forum,
  ),

  /// Learning analytics. Root: `/analytics`.
  analytics(
    rootPath: PRoutes.analytics,
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics,
  ),

  /// Courses — find/browse, plus joined courses at `/courses/:spaceid`.
  courses(rootPath: PRoutes.courses, icon: Icons.add, selectedIcon: Icons.add),

  /// Profile (formerly user_home). Root: `/profile`.
  profile(
    rootPath: PRoutes.profile,
    icon: Icons.account_circle_outlined,
    selectedIcon: Icons.account_circle,
  ),

  /// Settings. Root: `/settings`.
  settings(
    rootPath: PRoutes.settings,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  );

  const AppSection({
    required this.rootPath,
    required this.icon,
    required this.selectedIcon,
  });

  final String rootPath;
  final IconData icon;
  final IconData selectedIcon;

  /// First path segment owned by this section ('' for [chats]).
  String get _segment => rootPath == '/' ? '' : rootPath.substring(1);

  /// Resolve the active section from a location.
  ///
  /// `/rooms/...` (Matrix rooms) and first-class world-object URLs both
  /// belong to the chats/world surface. Unknown segments default to
  /// [chats] so the nav always has a sane selection.
  static AppSection fromUri(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty) return AppSection.chats;
    final first = segments.first;
    if (first == 'rooms') return AppSection.chats;
    if (PRoutes.isWorldObjectId(first)) return AppSection.chats;
    for (final section in AppSection.values) {
      if (section._segment == first) return section;
    }
    return AppSection.chats;
  }

  /// The space id when a joined course is active (`/courses/:spaceid`),
  /// else null. Literal subroutes of `/courses` (find/create flows) are
  /// not space ids — Matrix room ids start with `!`.
  static String? activeSpaceId(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first != 'courses') return null;
    final second = segments[1];
    return second.startsWith('!') ? second : null;
  }
}
