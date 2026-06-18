import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/close_affordance.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
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

  /// From the allocator: this panel is the surviving detail over a folded
  /// master, so its close becomes `←` (reveal the master). See `close_affordance`.
  final bool foldedOver;

  const WorkspaceRightPanel({
    super.key,
    required this.token,
    required this.currentUri,
    this.foldedOver = false,
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

    // Centralized close affordance (see close_affordance.dart). A `pushable`
    // detail whose param is a `/`-path is at a LEAF (`←` pops one page level via
    // popPage); a folded detail reveals its master (`←`); everything else
    // dismisses (`X`).
    final page = token.param;
    final pushable = PanelRegistry.defFor(token.type)?.pushable ?? false;
    final isPushed = pushable && page != null && page.contains('/');
    final aff =
        CloseAffordance.of(isPushedPage: isPushed, revealsMaster: foldedOver);
    final leadingIcon = aff.showBack ? Icons.arrow_back : Icons.close;
    final leadingTooltip = aff.showBack
        ? MaterialLocalizations.of(context).backButtonTooltip
        : l10n.close;
    final onLeading = aff.showBack && isPushed
        ? () => context.go(WorkspaceNav.popPage(currentUri, token.type, page))
        : () => _close(context);

    Widget card(String title, Widget child, {VoidCallback? onLeadingOverride}) =>
        _card(
          context,
          icon: leadingIcon,
          tooltip: leadingTooltip,
          onLeading: onLeadingOverride ?? onLeading,
          title: title,
          child: child,
        );

    switch (token.type) {
      case 'analytics':
        final (title, child) = _analytics(l10n, token.param);
        return card(title, child);
      case 'settings':
      case 'profile':
        // The settings/profile MENU master. Closing it drops its open page too
        // (the page has no meaning without the menu). The page opens beside it
        // as a `settingspage` detail (below).
        return card(
          l10n.settings,
          const SettingsPanel(),
          onLeadingOverride: () =>
              context.go(WorkspaceNav.closeSettings(currentUri)),
        );
      case 'settingspage':
        // The menu's detail: a settings/profile page. A top-level page's close
        // reveals the menu (X coexisting, ← folded); a `/`-leaf pushes, so ←
        // pops to its parent page (handled by [onLeading]).
        return card('', SettingsPanel(subPath: page));
      case 'vocab':
      case 'grammar':
        final construct = _construct;
        return card(
          construct?.lemma ?? '',
          ConstructAnalyticsView(
            view: token.type == 'vocab'
                ? ConstructTypeEnum.vocab
                : ConstructTypeEnum.morph,
            construct: construct,
            embedded: true,
          ),
        );
      default:
        // A registered right-panel type whose builder was retired (e.g. a stale
        // `review:` URL). Degrade to a closeable placeholder so it can never
        // become a width-reserving, close-less ghost.
        return card(l10n.oopsSomethingWentWrong, const SizedBox.shrink());
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
