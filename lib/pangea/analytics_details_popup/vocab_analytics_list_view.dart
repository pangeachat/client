import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_details_popup/vocab_analytics_list_tile.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Displays vocab analytics, sorted into categories
/// (flowers, greens, and seeds) by points
class VocabAnalyticsListView extends StatelessWidget {
  final void Function(ConstructIdentifier) onConstructZoom;

  List<ConstructUses> get vocab => MatrixState
      .pangeaController.getAnalytics.constructListModel
      .constructList(type: ConstructTypeEnum.vocab)
      .where((use) => use.lemma.isNotEmpty)
      .sorted((a, b) => a.lemma.toLowerCase().compareTo(b.lemma.toLowerCase()));

  const VocabAnalyticsListView({
    super.key,
    required this.onConstructZoom,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const InstructionsInlineTooltip(
          instructionsEnum: InstructionsEnum.analyticsVocabList,
        ),
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Row(
            spacing: 48.0,
            mainAxisAlignment: MainAxisAlignment.center,
            children: ConstructLevelEnum.values.reversed
                .map((constructLevelCategory) {
              final int count = vocab
                  .where((e) => e.lemmaCategory == constructLevelCategory)
                  .length;
              return Badge(
                label: Text(count.toString()),
                child: constructLevelCategory.icon(24),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 100.0,
                mainAxisExtent: 100.0,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
              ),
              itemCount: vocab.length,
              itemBuilder: (context, index) {
                final vocabItem = vocab[index];
                return VocabAnalyticsListTile(
                  onTap: () => onConstructZoom(vocabItem.id),
                  constructUse: vocabItem,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
