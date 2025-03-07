import 'package:collection/collection.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_constants.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/common/widgets/customized_svg.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

/// Displays vocab analytics, sorted into categories
/// (flowers, greens, and seeds) by points
class VocabAnalyticsListView extends StatelessWidget {
  final void Function(ConstructIdentifier) onConstructZoom;

  List<ConstructUses> get lemmas => MatrixState.pangeaController.getAnalytics.constructListModel
        .constructList(type: ConstructTypeEnum.vocab)
      ..sort((a, b) => a.lemma.toLowerCase().compareTo(b.lemma.toLowerCase()));

  const VocabAnalyticsListView({
    super.key,
    required this.onConstructZoom,
  });

  

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: ConstructLevelEnum.values.map((constructLevelCategory) {
            final int count = lemmas.where((e) => e.lemmaCategory == constructLevelCategory).length;
            return Badge(
              label: constructLevelCategory.icon,
              child: Text(count.toString()),
            );
          }).toList(),
        ),
        /// lemmas displated using EmojiChoiceItem
        const Wrap(),
      ],
    )
  }
}

class VocabChip {
  final ConstructUses construct;
  final String? displayText;

  VocabChip({
    required this.construct,
    this.displayText,
  });
}
