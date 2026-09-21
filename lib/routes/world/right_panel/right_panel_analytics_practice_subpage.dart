import 'package:flutter/material.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_page.dart';
import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The practice panel. Its ONE header (close + progress + timer + flag + End)
/// is rendered by [AnalyticsPractice]'s own view, so no [PanelCardWithHeader]
/// here. The close control leaves SILENTLY — the session survives in the
/// [PracticeSessionHolder]; only the header's explicit End control confirms
/// and discards. See routing.instructions.md § Practice is a persistent
/// background session.
class RightPanelAnalyticsPracticeSubpage extends StatelessWidget {
  final AnalyticsPracticeTokenParam param;
  final IconData icon;
  final String tooltip;
  final VoidCallback close;

  const RightPanelAnalyticsPracticeSubpage({
    super.key,
    required this.param,
    required this.icon,
    required this.tooltip,
    required this.close,
  });

  @override
  Widget build(BuildContext context) {
    final type = param.constructType;
    // The dispatcher's named group (#8729) is this panel's one container. It
    // is also the semantic boundary that confines the nested Navigator's
    // ModalBarrier BlockSemantics (#8459) — the wrapper that used to sit here
    // duplicated the identical "Practice page" group inside it.
    return PanelCard(
      child: Navigator(
        key: MatrixState.pAnyState
            .layerLinkAndKey("${type.name}_analytics_practice_page")
            .key,
        onGenerateRoute: (_) => MaterialPageRoute(
          // Name the route's own scopesRoute semantics node (see the room
          // subpage, #8729) — same name source as the panel group.
          builder: (context) => Semantics(
            namesRoute: true,
            // Keeps loose descendant text out of the route's name (#8729).
            explicitChildNodes: true,
            label: L10n.of(
              context,
            ).pageLabel(PanelTypesEnum.practice.displayName(L10n.of(context))),
            child: AnalyticsPractice(
              type: type,
              closeIcon: icon,
              closeTooltip: tooltip,
              close: close,
            ),
          ),
        ),
      ),
    );
  }
}
