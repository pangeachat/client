import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The "Add course" popover (world_v2): a small menu anchored to the rail
/// `+` button with three entry points. Replaces navigating straight to the
/// find-course page — adding a course is a choice between making one,
/// joining a private one by code, or browsing public ones.
///
/// Each option maps onto an existing `/courses` route.
enum _AddCourseAction { startMyOwn, enterCode, browsePublic }

/// Show the add-course menu anchored to [anchorContext] (the rail item).
/// Navigates to the chosen flow; does nothing if dismissed.
Future<void> showAddCourseMenu(BuildContext anchorContext) async {
  final l10n = L10n.of(anchorContext);
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
  final button = anchorContext.findRenderObject() as RenderBox;

  // Anchor the menu to the button's right edge so it opens beside the rail.
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(button.size.topRight(Offset.zero), ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );

  final action = await showMenu<_AddCourseAction>(
    context: anchorContext,
    position: position,
    items: [
      PopupMenuItem(
        value: _AddCourseAction.startMyOwn,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.auto_stories_outlined),
          title: Text(l10n.addCourseStartMyOwn),
        ),
      ),
      PopupMenuItem(
        value: _AddCourseAction.enterCode,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.vpn_key_outlined),
          title: Text(l10n.addCourseEnterCode),
        ),
      ),
      PopupMenuItem(
        value: _AddCourseAction.browsePublic,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.travel_explore_outlined),
          title: Text(l10n.addCourseBrowsePublic),
        ),
      ),
    ],
  );

  if (action == null || !anchorContext.mounted) return;

  switch (action) {
    case _AddCourseAction.startMyOwn:
      anchorContext.go('${PRoutes.courses}/own');
    case _AddCourseAction.enterCode:
      anchorContext.go('${PRoutes.courses}/private');
    case _AddCourseAction.browsePublic:
      anchorContext.go(PRoutes.courses);
  }
}
