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
/// section" and `route_facts.sectionFor` returns [courses]. Resolution of a
/// location to a section/space lives in route_facts.dart (the single source);
/// this enum is just the section identities (root path, icons).
enum AppSection {
  /// World map home. Root: `/`. The app opens onto the world; first-class
  /// world objects (`/<uuid>`) render over this surface.
  world(
    rootPath: PRoutes.world,
    icon: Icons.public_outlined,
    selectedIcon: Icons.public,
  ),

  /// Chats — the chat list. Root: `/chats`. Matrix rooms (`/rooms/...`)
  /// belong to this surface too.
  chats(
    rootPath: PRoutes.chats,
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
}
