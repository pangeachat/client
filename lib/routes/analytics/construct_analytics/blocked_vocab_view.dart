import 'dart:async';

import 'package:flutter/material.dart';

import 'package:diacritic/diacritic.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_init_error_indicator.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/restore_constructs_mixin.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/vocab_analytics_list_tile.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The deleted-vocab list — the undo surface for
/// [AnalyticsUpdateService.blockConstructs].
///
/// Pushed under the vocab summary as `analytics:vocab/deleted`, so the panel
/// host renders a back arrow that pops to the vocab list rather than closing
/// analytics outright. Unlike that list this page has no filters, search,
/// practice button, or overflow menu — see analytics-system.instructions.md.
class BlockedVocabView extends StatefulWidget {
  final Widget closeButton;

  const BlockedVocabView({super.key, required this.closeButton});

  @override
  State<BlockedVocabView> createState() => _BlockedVocabViewState();
}

class _BlockedVocabViewState extends State<BlockedVocabView>
    with ConstructRestorer {
  List<ConstructUses>? _blocked;
  final List<ConstructIdentifier> _selected = [];
  StreamSubscription<AnalyticsStreamUpdate>? _updateSub;

  bool get _selectMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    _updateSub = Matrix.of(context)
        .analyticsDataService
        .updateDispatcher
        .constructUpdateStream
        .stream
        .listen(_onConstructUpdate);
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  /// A restore prunes in place — the row leaves this list because room state
  /// changed. Anything else (a fresh block from another surface or device) is a
  /// refetch, since this page's contents are exactly the blocked set.
  void _onConstructUpdate(AnalyticsStreamUpdate update) {
    final restored = update.restoredConstructs;
    if (restored != null) {
      if (!mounted) return;
      setState(() {
        _blocked?.removeWhere((c) => restored.contains(c.id));
        _selected.removeWhere(restored.contains);
      });
      return;
    }
    _load();
  }

  Future<void> _load() async {
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) {
      if (mounted) setState(() => _blocked = []);
      return;
    }

    final data = await Matrix.of(context).analyticsDataService
        .getBlockedConstructs(ConstructTypeEnum.vocab, l2.langCodeShort);

    final sorted = data.values.toList()
      ..sort(
        (a, b) => removeDiacritics(
          a.lemma,
        ).toLowerCase().compareTo(removeDiacritics(b.lemma).toLowerCase()),
      );

    if (mounted) setState(() => _blocked = sorted);
  }

  void _toggleSelected(ConstructIdentifier id) => setState(() {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
  });

  Future<void> _restore(List<ConstructIdentifier> ids) async {
    final restored = await restoreConstructs(context, ids);
    if (!restored || !mounted) return;
    setState(_selected.clear);
  }

  void _openDetails(ConstructIdentifier id) =>
      AnalyticsNavigationUtil.navigateToAnalytics(
        context: context,
        view: ProgressIndicatorEnum.wordsUsed,
        construct: id,
      );

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;
    final blocked = _blocked;

    return Scaffold(
      appBar: AppBar(
        leading: Center(child: widget.closeButton),
        title: Text(
          L10n.of(context).deletedVocab,
          style: FluffyThemes.isColumnMode(context)
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Padding(
        padding: const EdgeInsetsGeometry.all(16.0),
        child: analyticsService.hasInitError
            ? AnalyticsInitErrorIndicator(
                reinitialize: analyticsService.reinitialize,
              )
            : blocked == null
            ? const Center(child: CircularProgressIndicator.adaptive())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectMode) _selectionRow(context),
                  Expanded(child: _grid(context, blocked)),
                ],
              ),
      ),
    );
  }

  Widget _selectionRow(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: L10n.of(context).deselectAll,
            onPressed: () => setState(_selected.clear),
            icon: const Icon(Icons.close),
          ),
          Text(
            "${_selected.length}",
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
      IconButton(
        tooltip: L10n.of(context).restore,
        onPressed: () => _restore(List.of(_selected)),
        icon: const Icon(Icons.restore_from_trash_outlined),
      ),
    ],
  );

  Widget _grid(BuildContext context, List<ConstructUses> blocked) =>
      CustomScrollView(
        key: const PageStorageKey("blocked-vocab-view-page-key"),
        slivers: [
          SliverToBoxAdapter(
            child: InstructionsInlineTooltip(
              instructionsEnum: blocked.isEmpty
                  ? InstructionsEnum.deletedVocabListEmpty
                  : InstructionsEnum.deletedVocabList,
            ),
          ),
          if (blocked.isNotEmpty)
            SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 100.0,
                mainAxisExtent: 100.0,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = blocked[index];
                return VocabAnalyticsListTile(
                  constructId: item.id,
                  level: item.lemmaCategory,
                  textColor: Theme.of(context).brightness == Brightness.light
                      ? item.lemmaCategory.darkColor(context)
                      : item.lemmaCategory.color(context),
                  selected: _selected.contains(item.id),
                  blocked: true,
                  onTap: _selectMode
                      ? () => _toggleSelected(item.id)
                      : () => _openDetails(item.id),
                  onLongPress: () => _toggleSelected(item.id),
                );
              }, childCount: blocked.length),
            ),
        ],
      );
}
