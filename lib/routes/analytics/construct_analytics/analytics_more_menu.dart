import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_dowload_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum _MoreMenuAction { deletedVocab, download }

/// The analytics summary's overflow menu.
///
/// Renders nothing when it would hold no items. The deleted-vocab entry is
/// vocab-only (nothing else can be blocked) and download is web-and-developer
/// only, so on the grammar tab an ordinary user would otherwise get a button
/// that opens an empty popup.
class AnalyticsMoreMenu extends StatelessWidget {
  final ConstructTypeEnum view;

  const AnalyticsMoreMenu({super.key, required this.view});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final showDeletedVocab = view == ConstructTypeEnum.vocab;
    final showDownload =
        kIsWeb &&
        MatrixState.pangeaController.userController.showDeveloperOptions;

    if (!showDeletedVocab && !showDownload) return const SizedBox.shrink();

    return PopupMenuButton<_MoreMenuAction>(
      useRootNavigator: true,
      // PopupMenuButton is not covered by the a11y floor check, but an unnamed
      // one falls back to the framework default and Playwright resolves controls
      // by accessible name.
      tooltip: l10n.moreOptions,
      onSelected: (action) {
        switch (action) {
          case _MoreMenuAction.deletedVocab:
            context.go(
              WorkspaceNav.openBlockedVocabList(GoRouterState.of(context).uri),
            );
          case _MoreMenuAction.download:
            showDialog<AnalyticsDownloadDialog>(
              context: context,
              builder: (context) => const AnalyticsDownloadDialog(),
            );
        }
      },
      itemBuilder: (context) => [
        if (showDeletedVocab)
          PopupMenuItem<_MoreMenuAction>(
            value: _MoreMenuAction.deletedVocab,
            child: Row(
              children: [
                const Icon(Icons.delete_outline),
                const SizedBox(width: 12),
                Text(l10n.deletedVocab),
              ],
            ),
          ),
        if (showDownload)
          PopupMenuItem<_MoreMenuAction>(
            value: _MoreMenuAction.download,
            child: Row(
              children: [
                const Icon(Symbols.download),
                const SizedBox(width: 12),
                Text(l10n.download),
              ],
            ),
          ),
      ],
    );
  }
}
