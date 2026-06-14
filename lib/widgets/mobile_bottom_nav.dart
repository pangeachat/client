import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pangea_icon_button.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Mobile bottom navigation (world_v2). The wide rail collapses to a bottom
/// bar on narrow screens: World · Chats · Analytics · Avatar · Add, plus a
/// selected-space switcher slot that opens a sheet of joined courses.
/// Section roots show the bar; details push over it.
class MobileBottomNav extends StatelessWidget {
  final GoRouterState state;
  const MobileBottomNav({required this.state, super.key});

  @override
  Widget build(BuildContext context) {
    final section = AppSection.fromUri(state.uri);
    final activeSpaceId = AppSection.activeSpaceId(state.uri);
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
                onPressed: () => context.go(PRoutes.world),
              ),
              _NavButton(
                icon: Icons.forum_outlined,
                selectedIcon: Icons.forum,
                selected: section == AppSection.chats,
                tooltip: L10n.of(context).allChats,
                onTap: () => context.go(PRoutes.chats),
              ),
              _NavButton(
                icon: Icons.analytics_outlined,
                selectedIcon: Icons.analytics,
                selected: section == AppSection.analytics,
                tooltip: L10n.of(context).learningAnalytics,
                onTap: () =>
                    AnalyticsNavigationUtil.navigateToAnalytics(context: context),
              ),
              _SpaceSwitcherButton(activeSpaceId: activeSpaceId),
              _NavButton(
                icon: Icons.account_circle_outlined,
                selectedIcon: Icons.account_circle,
                selected:
                    section == AppSection.profile ||
                    section == AppSection.settings,
                tooltip: L10n.of(context).profile,
                onTap: () => context.go(PRoutes.profile),
              ),
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

    return InkWell(
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
            : Icon(Icons.school_outlined, color: theme.colorScheme.outline),
      ),
    );
  }
}

Future<void> _showSpaceSwitcherSheet(BuildContext context) {
  final client = Matrix.of(context).client;
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
                sheetContext.go(PRoutes.course(space.id));
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
