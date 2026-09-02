import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/close_affordance.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/routes/world/right_panel/panel_card_with_header.dart';
import 'package:fluffychat/routes/world/right_panel/right_panel_analytics_practice_subpage.dart';
import 'package:fluffychat/routes/world/right_panel/right_panel_analytics_subpage.dart';
import 'package:fluffychat/routes/world/right_panel/right_panel_settings_subpage.dart';
import 'package:fluffychat/routes/world/settings_page_enum.dart';

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

  /// Close reads the LIVE router URI, never the constructor-captured
  /// [currentUri]: a close action can fire after an async gap (e.g. the practice
  /// exit-confirmation dialog) or a stream-driven rebuild, by which point a
  /// captured URI is stale and closeRight would compute off the wrong state —
  /// the intermittent "X stops working" (#7247). [currentUri] stays the
  /// build-time input for rendering the icon (the widget rebuilds on URL change).
  void _close(BuildContext context) => context.go(
    WorkspaceNav.closeRight(
      GoRouter.of(context).routeInformationProvider.value.uri,
      token,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    // Centralized close affordance (see close_affordance.dart). A `pushable`
    // detail whose param is a `/`-path is at a page LEAF (`←` pops one page level
    // via popPage). Closing returns to a master behind it (`←`) when this panel is
    // a width-folded detail OR — on a narrow single pane, where only the focused
    // leaf is drawn — when this leaf's navigation-tree parent is open behind it;
    // an independent panel (no open parent) dismisses to the map (`X`).

    final pushable = token.type.def.pushable;
    final isPushed = pushable && token.param?.isPushed == true;
    final revealsMaster =
        foldedOver || (!isColumnMode && parentIsOpen(currentUri, token));

    final aff = CloseAffordance.of(
      isPushedPage: isPushed,
      revealsMaster: revealsMaster,
    );

    final leadingIcon = aff.showBack ? Icons.arrow_back : Icons.close;

    String? closeButtonLabel;
    if (token is SettingsPagePanelToken) {
      final settingsToken = token as SettingsPagePanelToken;
      closeButtonLabel = SettingsPageEnum.fromString(
        settingsToken.param?.subpage,
      ).title(l10n);
    }
    // An analytics drilldown (Level / Vocab / Grammar / Activities) is named
    // by its own visible title, like a settings page — "Stats page" for the
    // Level drilldown mislabeled both its group and its close control (#8729).
    if (token is AnalyticsPanelToken) {
      closeButtonLabel = (token as AnalyticsPanelToken).param?.subpage.tooltip(
        context,
      );
    }

    final leadingTooltip = aff.showBack
        ? MaterialLocalizations.of(context).backButtonTooltip
        : token.type.closeButtonLabel(l10n, named: closeButtonLabel);

    final onLeading = aff.showBack && isPushed
        ? () => context.go(
            WorkspaceNav.popPage(
              GoRouter.of(context).routeInformationProvider.value.uri,
              token,
            ),
          )
        : () => _close(context);

    final Widget panel = switch (token) {
      AnalyticsPanelToken(param: final param) => RightPanelAnalyticsSubpage(
        param: param,
        icon: leadingIcon,
        onLeading: onLeading,
        tooltip: leadingTooltip,
      ),
      SettingsPanelToken() => PanelCardWithHeader(
        title: l10n.settings,
        icon: leadingIcon,
        onLeading: () => context.go(
          WorkspaceNav.closeSettings(
            GoRouter.of(context).routeInformationProvider.value.uri,
          ),
        ),
        tooltip: leadingTooltip,
        child: RightPanelSettingsSubpage(
          closeButton: IconButton(
            tooltip: leadingTooltip,
            icon: Icon(leadingIcon),
            onPressed: onLeading,
          ),
        ),
      ),
      SettingsPagePanelToken(param: final param) => () {
        final settingsPage = SettingsPageEnum.fromString(param?.subpage);
        final settingsCloseButton = IconButton(
          tooltip: leadingTooltip,
          icon: Icon(leadingIcon),
          onPressed: onLeading,
        );

        // The shared header is the DEFAULT for a settings detail; only a page
        // that draws its own chrome opts out (SettingsPageEnum.addHeader).
        // Dropping the wrapper wholesale left every classic page (learning,
        // style, notifications, devices, chat, security, password, profile)
        // with no title and no way out (#7763).
        return settingsPage.addHeader
            ? PanelCardWithHeader(
                title: settingsPage.title(l10n),
                icon: leadingIcon,
                onLeading: onLeading,
                tooltip: leadingTooltip,
                child: RightPanelSettingsSubpage(
                  param: param,
                  closeButton: settingsCloseButton,
                ),
              )
            : PanelCard(
                child: RightPanelSettingsSubpage(
                  param: param,
                  closeButton: settingsCloseButton,
                ),
              );
      }(),
      VocabAnalyticsPanelToken(param: final param) => PanelCard(
        child: ConstructAnalyticsView(
          view: ConstructTypeEnum.vocab,
          construct: param?.constructId,
          closeButton: IconButton(
            tooltip: leadingTooltip,
            icon: Icon(leadingIcon),
            onPressed: onLeading,
          ),
        ),
      ),
      GrammarAnalyticsPanelToken(param: final param) => PanelCard(
        child: ConstructAnalyticsView(
          view: ConstructTypeEnum.morph,
          construct: param?.constructId,
          closeButton: IconButton(
            tooltip: leadingTooltip,
            icon: Icon(leadingIcon),
            onPressed: onLeading,
          ),
        ),
      ),
      AnalyticsPracticePanelToken(param: final param) =>
        param == null
            ? const SizedBox.shrink()
            : RightPanelAnalyticsPracticeSubpage(
                param: param,
                icon: leadingIcon,
                tooltip: leadingTooltip,
                close: () => _close(context),
              ),
      _ => PanelCardWithHeader(
        title: l10n.oopsSomethingWentWrong,
        icon: leadingIcon,
        onLeading: onLeading,
        tooltip: leadingTooltip,
        child: const SizedBox.shrink(),
      ),
    };

    // Every workspace panel is one named semantic group (#8729) — authored
    // here, where every right-column token resolves, so a panel cannot miss
    // it by drawing its own chrome. The settings-page title reuses the same
    // computed subpage title its close label carries, so the group and its
    // "Close X" always agree.
    return Semantics(
      label: l10n.pageLabel(closeButtonLabel ?? token.type.displayName(l10n)),
      container: true,
      // Keep descendants as their own nodes: without this, loose text with no
      // container of its own (the Level drilldown's "LVL 15 … XP" header)
      // merges INTO the panel's name, announcing as one garbled label.
      explicitChildNodes: true,
      child: panel,
    );
  }
}
