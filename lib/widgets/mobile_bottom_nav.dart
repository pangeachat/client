import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pangea_icon_button.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Mobile bottom navigation (world_v2) — the section switcher only: **World**,
/// **Chats**, and a course-switcher slot (a sheet of joined courses). Analytics
/// and Profile are reached from the top-right cluster, not here. The shell shows
/// this bar only at a section root (the map, the chat list, the courses list);
/// a focused detail hides it, and a bottom sheet (a course, a tapped pin)
/// replaces it. See `routing.instructions.md`.
class MobileBottomNav extends StatelessWidget {
  final GoRouterState state;
  const MobileBottomNav({required this.state, super.key});

  @override
  Widget build(BuildContext context) {
    final section = sectionFor(state.uri);
    final activeSpaceId = activeSpaceIdFor(state.uri);
    final theme = Theme.of(context);

    return Material(
      elevation: 3,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              PangeaIconButton(
                selected: section == AppSection.world,
                tooltip: L10n.of(context).world,
                // World is home: clear every panel and reveal the full map.
                onPressed: () => context.go(WorkspaceNav.clearAll()),
              ),
              _NavButton(
                icon: Icons.forum_outlined,
                selectedIcon: Icons.forum,
                selected: section == AppSection.chats,
                tooltip: L10n.of(context).allChats,
                onTap: () => context.go(
                  WorkspaceNav.setSection(
                    state.uri,
                    PRoutes.world,
                    const PanelToken('chats'),
                    // A nav click replaces the open panels rather than stacking.
                    keepRoom: false,
                  ),
                ),
              ),
              // Analytics and Profile are reached from the top-right cluster (its
              // trackers / avatar), not the bottom nav — the bar is only the
              // section switcher (World / Chats / Courses). See
              // routing.instructions.md.
              _SpaceSwitcherButton(activeSpaceId: activeSpaceId),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(
        selected ? selectedIcon : icon,
        color: selected ? theme.colorScheme.primary : null,
      ),
    );
  }
}

/// The collapsed space slot: shows the selected course (or an add icon when
/// none) and opens the joined-courses switcher sheet on tap.
class _SpaceSwitcherButton extends StatelessWidget {
  final String? activeSpaceId;
  const _SpaceSwitcherButton({required this.activeSpaceId});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final active = activeSpaceId != null
        ? client.getRoomById(activeSpaceId!)
        : null;
    final theme = Theme.of(context);

    return Tooltip(
      message: active != null
          ? active.getLocalizedDisplayname(MatrixLocals(L10n.of(context)))
          : L10n.of(context).courses,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => _showSpaceSwitcherSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: active != null
              ? Avatar(
                  mxContent: active.avatar,
                  name: active.getLocalizedDisplayname(
                    MatrixLocals(L10n.of(context)),
                  ),
                  size: 32,
                  borderRadius: BorderRadius.circular(8),
                )
              : Icon(Icons.map_outlined, color: theme.colorScheme.outline),
        ),
      ),
    );
  }
}

Future<void> _showSpaceSwitcherSheet(BuildContext context) {
  final client = Matrix.of(context).client;
  final uri = GoRouterState.of(context).uri;
  final spaces = client.rooms
      .where((r) => r.isSpace && r.membership == Membership.join)
      .toList();

  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final space in spaces)
            ListTile(
              leading: Avatar(
                mxContent: space.avatar,
                name: space.getLocalizedDisplayname(
                  MatrixLocals(L10n.of(sheetContext)),
                ),
                size: 36,
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(
                space.getLocalizedDisplayname(
                  MatrixLocals(L10n.of(sheetContext)),
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                sheetContext.go(
                  WorkspaceNav.setSection(
                    uri,
                    PRoutes.course(space.id),
                    const PanelToken('course'),
                    keepRoom: false,
                  ),
                );
              },
            ),
          const Divider(height: 1),
          // Add-course options inline (the desktop rail uses a popover;
          // on mobile the sheet hosts the choices directly).
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(L10n.of(sheetContext).addCourseStartMyOwn),
            onTap: () {
              Navigator.of(sheetContext).pop();
              sheetContext.go('${PRoutes.courses}/own');
            },
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(L10n.of(sheetContext).addCourseEnterCode),
            onTap: () {
              Navigator.of(sheetContext).pop();
              sheetContext.go('${PRoutes.courses}/private');
            },
          ),
          ListTile(
            leading: const Icon(Icons.travel_explore_outlined),
            title: Text(L10n.of(sheetContext).addCourseBrowsePublic),
            onTap: () {
              Navigator.of(sheetContext).pop();
              sheetContext.go('${PRoutes.courses}/browse');
            },
          ),
        ],
      ),
    ),
  );
}
