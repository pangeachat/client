import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/level/level_analytics_details_content.dart';
import 'package:fluffychat/routes/world/settings_panel.dart';

/// Renders one right-column panel token as a rounded card floating over the map.
/// The header carries the close (a summary/review) or back (a detail blooming
/// left of its summary) control, which mutates the URL through [WorkspaceNav] —
/// the panel set is URL state, so closing is just `context.go` to a URL without
/// this token. See `routing.instructions.md`.
class WorkspaceRightPanel extends StatelessWidget {
  final PanelToken token;

  /// The current URL, so close/back can rewrite the `right=` list off it.
  final Uri currentUri;

  /// Collapsed to a thin tappable stripe (the allocator ran out of room).
  /// Tapping re-opens it at full width.
  final bool peek;

  const WorkspaceRightPanel({
    super.key,
    required this.token,
    required this.currentUri,
    this.peek = false,
  });

  ConstructIdentifier? get _construct {
    final param = token.param;
    if (param == null) return null;
    try {
      return ConstructIdentifier.fromJson(jsonDecode(param));
    } catch (_) {
      return null;
    }
  }

  void _close(BuildContext context) =>
      context.go(WorkspaceNav.closeRight(currentUri, token));

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    if (peek) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 4,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              context.go(WorkspaceNav.openRight(currentUri, token)),
          child: const Center(child: Icon(Icons.chevron_left)),
        ),
      );
    }

    switch (token.type) {
      case 'analytics':
        final (title, child) = _analytics(l10n, token.param);
        return _card(context, icon: Icons.close, title: title, child: child);
      case 'settings':
      case 'profile':
        // The whole profile + settings tree in one right-column panel. The menu
        // is the top level (close X); a sub-page is a push (back arrow pops one
        // level). Identity is the token param. See routing.instructions.md.
        final page = token.param;
        final isMenu = page == null || page.isEmpty;
        return _card(
          context,
          icon: isMenu ? Icons.close : Icons.arrow_back,
          tooltip: isMenu
              ? l10n.close
              : MaterialLocalizations.of(context).backButtonTooltip,
          title: isMenu ? l10n.settings : '',
          onLeading: isMenu
              ? null
              : () => context.go(WorkspaceNav.settingsBack(currentUri, page)),
          child: SettingsPanel(subPath: page),
        );
      case 'vocab':
      case 'grammar':
        final construct = _construct;
        return _card(
          context,
          icon: Icons.arrow_back,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          title: construct?.lemma ?? '',
          child: ConstructAnalyticsView(
            view: token.type == 'vocab'
                ? ConstructTypeEnum.vocab
                : ConstructTypeEnum.morph,
            construct: construct,
            embedded: true,
          ),
        );
      default:
        // A registered right-panel type whose builder was retired (e.g. a stale
        // `review:` URL from before a completed activity opened as its own
        // chat). Degrade to a closeable placeholder so it can never become a
        // width-reserving, close-less ghost. See routing.instructions.md.
        return _card(
          context,
          icon: Icons.close,
          title: l10n.oopsSomethingWentWrong,
          child: const SizedBox.shrink(),
        );
    }
  }

  (String, Widget) _analytics(L10n l10n, String? tab) {
    switch (tab) {
      case 'grammar':
        return (
          l10n.grammar,
          const ConstructAnalyticsView(
            view: ConstructTypeEnum.morph,
            embedded: true,
          ),
        );
      case 'sessions':
        return (l10n.activities, const ActivityArchive(embedded: true));
      case 'level':
        return (l10n.level, const LevelAnalyticsDetailsContent(embedded: true));
      case 'vocab':
      default:
        return (
          l10n.vocab,
          const ConstructAnalyticsView(
            view: ConstructTypeEnum.vocab,
            embedded: true,
          ),
        );
    }
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
    String? tooltip,
    VoidCallback? onLeading,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: tooltip ?? L10n.of(context).close,
                  icon: Icon(icon),
                  onPressed: onLeading ?? () => _close(context),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
