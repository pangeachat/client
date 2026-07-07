import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/close_affordance.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/grammar_analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/settings_token.dart';
import 'package:fluffychat/features/navigation/token_params/vocab_analytics_token_param.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_download_button.dart';
import 'package:fluffychat/routes/world/close_button_labels.dart';
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
    final type = token.type;
    final param = token.param;

    final pushable = PanelRegistry.defFor(type)?.pushable ?? false;
    final isPushed = pushable && param != null && param.isPushed;
    final revealsMaster =
        foldedOver || (!isColumnMode && parentIsOpen(currentUri, token));

    final aff = CloseAffordance.of(
      isPushedPage: isPushed,
      revealsMaster: revealsMaster,
    );

    final leadingIcon = aff.showBack ? Icons.arrow_back : Icons.close;

    final leadingTooltip = aff.showBack
        ? MaterialLocalizations.of(context).backButtonTooltip
        : closeButtonLabel(
            l10n,
            token,
            named: param is SettingsTokenParam
                ? SettingsPageEnum.fromString(param.subpage).title(l10n)
                : null,
          );

    final onLeading = aff.showBack && isPushed
        ? () => context.go(
            WorkspaceNav.popPage(
              GoRouter.of(context).routeInformationProvider.value.uri,
              type,
              param,
            ),
          )
        : () => _close(context);

    switch (type) {
      case 'analytics':
        return RightPanelAnalyticsSubpage(
          param: param is AnalyticsTokenParam ? param : null,
          icon: leadingIcon,
          onLeading: onLeading,
          tooltip: leadingTooltip,
        );
      case 'settings':
        return PanelCardWithHeader(
          title: l10n.settings,
          icon: leadingIcon,
          onLeading: () => context.go(
            WorkspaceNav.closeSettings(
              GoRouter.of(context).routeInformationProvider.value.uri,
            ),
          ),
          tooltip: leadingTooltip,
          child: RightPanelSettingsSubpage(),
        );
      case 'settingspage':
        final parsed = param is SettingsTokenParam ? param : null;
        final settingsPage = parsed != null
            ? SettingsPageEnum.fromString(parsed.subpage)
            : null;
        return settingsPage != null && settingsPage.addHeader
            ? PanelCardWithHeader(
                title: settingsPage.title(l10n),
                icon: leadingIcon,
                onLeading: onLeading,
                tooltip: leadingTooltip,
                child: RightPanelSettingsSubpage(param: parsed),
              )
            : PanelCard(
                child: RightPanelSettingsSubpage(
                  param: parsed,
                  closeButton: IconButton(
                    tooltip: leadingTooltip,
                    icon: Icon(leadingIcon),
                    onPressed: onLeading,
                  ),
                ),
              );
      case 'vocab':
        final parsed = param is VocabAnalyticsTokenParam ? param : null;
        return PanelCardWithHeader(
          title: '',
          icon: leadingIcon,
          onLeading: onLeading,
          tooltip: leadingTooltip,
          trailing: kIsWeb && parsed?.constructId == null
              ? DownloadAnalyticsButton()
              : null,
          child: ConstructAnalyticsView(
            view: ConstructTypeEnum.vocab,
            construct: parsed?.constructId,
          ),
        );
      case 'grammar':
        final parsed = param is GrammarAnalyticsTokenParam ? param : null;
        return PanelCardWithHeader(
          title: '',
          icon: leadingIcon,
          onLeading: onLeading,
          tooltip: leadingTooltip,
          trailing: kIsWeb && parsed?.constructId == null
              ? DownloadAnalyticsButton()
              : null,
          child: ConstructAnalyticsView(
            view: ConstructTypeEnum.morph,
            construct: parsed?.constructId,
          ),
        );
      case 'practice':
        if (param is! AnalyticsPracticeTokenParam) {
          return SizedBox.shrink();
        }

        return RightPanelAnalyticsPracticeSubpage(
          param: param,
          icon: leadingIcon,
          tooltip: leadingTooltip,
          close: () => _close(context),
        );
      default:
        return PanelCardWithHeader(
          title: l10n.oopsSomethingWentWrong,
          icon: leadingIcon,
          onLeading: onLeading,
          tooltip: leadingTooltip,
          child: const SizedBox.shrink(),
        );
    }
  }
}
