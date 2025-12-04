import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_popup.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_page/activity_archive.dart';
import 'package:fluffychat/pangea/analytics_page/analytics_page_constants.dart';
import 'package:fluffychat/pangea/analytics_summary/learning_progress_indicators.dart';
import 'package:fluffychat/pangea/analytics_summary/level_dialog_content.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsPage extends StatelessWidget {
  final ProgressIndicatorEnum? indicator;
  final ConstructIdentifier? construct;
  final bool isSidebar;

  const AnalyticsPage({
    super.key,
    this.indicator,
    this.construct,
    this.isSidebar = false,
  });

  Future<void> _blockLemma(BuildContext context) async {
    final resp = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: L10n.of(context).blockLemmaConfirmation,
      isDestructive: true,
    );

    if (resp != OkCancelResult.ok) return;
    final res = await showFutureLoadingDialog(
      context: context,
      future: () =>
          MatrixState.pangeaController.putAnalytics.blockConstruct(construct!),
    );

    if (!res.isError) {
      context.go("/rooms/analytics/${ConstructTypeEnum.vocab.name}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final analyticsRoomId = GoRouterState.of(context).pathParameters['roomid'];
    return Scaffold(
      appBar: construct != null
          ? AppBar(
              actions: indicator == ProgressIndicatorEnum.wordsUsed
                  ? [
                      IconButton(
                        icon: const Icon(Icons.delete_forever_outlined),
                        color: Theme.of(context).colorScheme.error,
                        tooltip: L10n.of(context).delete,
                        onPressed: () => _blockLemma(context),
                      ),
                    ]
                  : null,
            )
          : null,
      body: SafeArea(
        child: FutureBuilder(
          future:
              MatrixState.pangeaController.getAnalytics.initCompleter.future,
          builder: (context, snapshot) {
            return Padding(
              padding: const EdgeInsetsGeometry.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSidebar ||
                      (!FluffyThemes.isColumnMode(context) &&
                          construct == null))
                    LearningProgressIndicators(
                      selected: indicator,
                      canSelect: indicator != ProgressIndicatorEnum.level,
                    ),
                  Expanded(
                    child: () {
                      if (indicator == ProgressIndicatorEnum.level) {
                        return const LevelDialogContent();
                      } else if (indicator ==
                          ProgressIndicatorEnum.morphsUsed) {
                        return ConstructAnalyticsView(
                          construct: construct,
                          view: ConstructTypeEnum.morph,
                        );
                      } else if (indicator == ProgressIndicatorEnum.wordsUsed) {
                        return ConstructAnalyticsView(
                          construct: construct,
                          view: ConstructTypeEnum.vocab,
                        );
                      } else if (indicator ==
                          ProgressIndicatorEnum.activities) {
                        return ActivityArchive(
                          selectedRoomId: analyticsRoomId,
                        );
                      }

                      return Center(
                        child: SizedBox(
                          width: 250.0,
                          child: CachedNetworkImage(
                            imageUrl:
                                "${AppConfig.assetsBaseURL}/${AnalyticsPageConstants.dinoBotFileName}",
                            errorWidget: (context, url, error) =>
                                const SizedBox(),
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator.adaptive(),
                            ),
                          ),
                        ),
                      );
                    }(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
