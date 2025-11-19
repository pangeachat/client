import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/word_zoom_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityVocabWidget extends StatelessWidget {
  final List<Vocab> vocab;
  final String langCode;
  final String targetId;
  final ValueNotifier<Set<String>>? usedVocab;

  const ActivityVocabWidget({
    super.key,
    required this.vocab,
    required this.langCode,
    required this.targetId,
    required this.usedVocab,
  });

  @override
  Widget build(BuildContext context) {
    if (usedVocab == null) {
      return Wrap(
        spacing: 4.0,
        runSpacing: 4.0,
        children: [
          ...vocab.map(
            (vocab) => _VocabChip(
              vocab: vocab,
              targetId: targetId,
              langCode: langCode,
              usedVocab: const {},
            ),
          ),
        ],
      );
    }

    return ValueListenableBuilder(
      valueListenable: usedVocab!,
      builder: (context, used, __) {
        return Wrap(
          spacing: 4.0,
          runSpacing: 4.0,
          children: [
            ...vocab.map(
              (vocab) => _VocabChip(
                vocab: vocab,
                targetId: targetId,
                langCode: langCode,
                usedVocab: used,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VocabChip extends StatelessWidget {
  final Vocab vocab;
  final String targetId;
  final String langCode;
  final Set<String> usedVocab;

  const _VocabChip({
    required this.vocab,
    required this.targetId,
    required this.langCode,
    required this.usedVocab,
  });

  void _onTap(BuildContext context) {
    final target = "$targetId-${vocab.lemma}";
    OverlayUtil.showPositionedCard(
      overlayKey: target,
      context: context,
      cardToShow: WordZoomWidget(
        token: PangeaTokenText(
          content: vocab.lemma,
          length: vocab.lemma.characters.length,
          offset: 0,
        ),
        construct: ConstructIdentifier(
          lemma: vocab.lemma,
          type: ConstructTypeEnum.vocab,
          category: vocab.pos,
        ),
        langCode: langCode,
        onClose: () {
          MatrixState.pAnyState.closeOverlay(target);
        },
      ),
      transformTargetId: target,
      closePrevOverlay: false,
      addBorder: false,
      maxWidth: AppConfig.toolbarMinWidth,
      maxHeight: AppConfig.toolbarMaxHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = "$targetId-${vocab.lemma}";
    final color = usedVocab.contains(vocab.lemma.toLowerCase())
        ? Color.alphaBlend(
            Theme.of(context).colorScheme.surface.withAlpha(150),
            AppConfig.gold,
          )
        : Colors.transparent;

    final linkAndKey = MatrixState.pAnyState.layerLinkAndKey(target);
    return CompositedTransformTarget(
      link: linkAndKey.link,
      child: InkWell(
        key: linkAndKey.key,
        borderRadius: BorderRadius.circular(
          24.0,
        ),
        onTap: () => _onTap(context),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8.0,
            vertical: 4.0,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            vocab.lemma,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14.0,
            ),
          ),
        ),
      ),
    );
  }
}
