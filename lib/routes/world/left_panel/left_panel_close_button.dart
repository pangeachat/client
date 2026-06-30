import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/close_affordance.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/close_button_labels.dart';

/// The panel's close control. A pushed sub-page ([_isPushedSubPage]) backs out
/// ONE level via popPage (a course management page → the card; a room sub-page
/// → the chat). Otherwise the centralized [CloseAffordance] decides `←` (reveal
/// a folded/sibling master) vs `X` (dismiss to the map). See
/// `close_affordance` / `routing.instructions.md`.
class LeftPanelCloseButton extends StatelessWidget {
  final PanelToken token;
  final Uri currentUri;
  final bool foldedOver;
  final bool isColumnMode;

  const LeftPanelCloseButton({
    super.key,
    required this.token,
    required this.currentUri,
    required this.foldedOver,
    required this.isColumnMode,
  });

  /// True when this panel's param is a pushed sub-page (not the bare panel / a
  /// card tab): a `room`/`session` token carrying a `<roomid>/<sub>` path. Such
  /// a page's close is `←` back one level (popPage), not `X` to the map. (A
  /// course-management page is its own `coursepage` detail with its own close,
  /// not a push on the room/course token.) See `close_affordance`.
  bool get _isPushedSubPage {
    final page = token.param;
    if (page == null) return false;
    if (token.type == 'room' || token.type == 'session') {
      // The bare room id has no `/`; any `/` is a pushed sub-page beyond it.
      return page.contains('/');
    }
    return false;
  }

  // Centralized affordance (close_affordance.dart): `←` when closing returns to
  // a master that was behind us — a width-fold ([foldedOver]) or, on a narrow
  // single pane, this leaf's navigation-tree PARENT being open behind it
  // (possibly in the other column, e.g. a left session over the right analytics
  // list). An independent panel (no open parent) gets `X` so it dismisses to the
  // map in one tap, rather than a misleading `←` to something unrelated.
  CloseAffordance get _closeAffordance => CloseAffordance.of(
    isPushedPage: false,
    revealsMaster:
        foldedOver || (!isColumnMode && parentIsOpen(currentUri, token)),
  );

  /// The LIVE workspace URL at click time. The left panel does NOT rebuild when
  /// only the RIGHT column changes (so the live chat/timeline is not torn down),
  /// so the [currentUri] captured at this panel's last build can be STALE for the
  /// right column. A token mutation (close / pop) preserves the rest of the query
  /// verbatim, so running it on the stale uri would "restore" the right tab the
  /// panel opened with and discard whatever the user switched to since — e.g.
  /// closing a session review snapped the right column from `analytics:grammar`
  /// back to the open-time `analytics:sessions` (#7268). Read the current url
  /// instead, so the close drops only this token and leaves the right column as
  /// the user left it.
  Uri _liveUri(BuildContext context) =>
      GoRouter.of(context).routeInformationProvider.value.uri;

  // A `room`/`session` is a token-only panel, so dropping its token closes it.
  // A section panel (a course) is also addressable by its map filter, so
  // closing it returns to the world map. See WorkspaceNav.closeSection.
  void _close(BuildContext context) {
    final uri = _liveUri(context);
    context.go(
      token.type == 'room' || token.type == 'session'
          ? WorkspaceNav.closeLeft(uri, token)
          : WorkspaceNav.closeSection(uri, token),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = token.param;
    if (_isPushedSubPage && page != null) {
      return BackButton(
        onPressed: () => context.go(
          WorkspaceNav.popPage(_liveUri(context), token.type, page),
        ),
      );
    }

    return _closeAffordance.showBack
        ? BackButton(onPressed: () => _close(context))
        : IconButton(
            icon: const Icon(Icons.close),
            tooltip: closeButtonLabel(L10n.of(context), token),
            onPressed: () => _close(context),
          );
  }
}
