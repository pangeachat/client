import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/token_rendering_util.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/tokens_util.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/underline_text_widget.dart';
import 'package:fluffychat/pangea/toolbar/token_rendering_mixin.dart';
import 'package:fluffychat/pangea/toolbar/word_card/word_zoom_widget.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityVocabWidget extends StatelessWidget {
  final List<Vocab> vocab;
  final String langCode;
  final String targetId;
  final String activityLangCode;
  final ValueNotifier<Set<String>>? usedVocab;

  const ActivityVocabWidget({
    super.key,
    required this.vocab,
    required this.langCode,
    required this.targetId,
    required this.activityLangCode,
    this.usedVocab,
  });

  @override
  Widget build(BuildContext context) {
    if (usedVocab == null) {
      return _VocabChips(
        vocab: vocab,
        targetId: targetId,
        langCode: langCode,
        usedVocab: const {},
        activityLangCode: activityLangCode,
      );
    }

    return ValueListenableBuilder(
      valueListenable: usedVocab!,
      builder: (context, used, _) => _VocabChips(
        vocab: vocab,
        targetId: targetId,
        langCode: langCode,
        usedVocab: used,
        activityLangCode: activityLangCode,
      ),
    );
  }
}

class _VocabChips extends StatefulWidget {
  final List<Vocab> vocab;
  final String targetId;
  final String langCode;
  final String activityLangCode;
  final Set<String> usedVocab;

  const _VocabChips({
    required this.vocab,
    required this.targetId,
    required this.langCode,
    required this.activityLangCode,
    required this.usedVocab,
  });

  @override
  State<_VocabChips> createState() => _VocabChipsState();
}

class _VocabChipsState extends State<_VocabChips> with TokenRenderingMixin {
  Vocab? _selectedVocab;

  @override
  void dispose() {
    TokensUtil.clearNewTokenCache();
    super.dispose();
  }

  void _onTap(Vocab v, bool isNew) {
    setState(() {
      _selectedVocab = v;
    });

    final target = "${widget.targetId}-${v.lemma}";
    if (isNew) {
      final token = v.asToken();
      collectNewToken(
        "activity_tokens",
        widget.targetId,
        token,
        Matrix.of(context).analyticsDataService,
      ).then((_) {
        if (mounted) setState(() {});
      });
    }
    OverlayUtil.showPositionedCard(
      overlayKey: target,
      context: context,
      cardToShow: _WordCardWrapper(
        v: v,
        langCode: widget.langCode,
        target: target,
        onClose: () {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _selectedVocab = null),
            );
          }
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
    final tokens = widget.vocab.map((v) => v.asToken()).toList();
    final newTokens = TokensUtil.getNewTokens(
      "activity_tokens",
      tokens,
      widget.activityLangCode,
    );

    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      children: [
        ...widget.vocab.map((v) {
          final target = "${widget.targetId}-${v.lemma}";
          final color = widget.usedVocab.contains(v.lemma.toLowerCase())
              ? Color.alphaBlend(
                  Theme.of(context).colorScheme.surface.withAlpha(150),
                  AppConfig.gold,
                )
              : Theme.of(context).colorScheme.primary.withAlpha(20);

          final linkAndKey = MatrixState.pAnyState.layerLinkAndKey(target);
          final isNew = newTokens.any(
            (t) => t.content.toLowerCase() == v.lemma.toLowerCase(),
          );

          return CompositedTransformTarget(
            link: linkAndKey.link,
            child: InkWell(
              key: linkAndKey.key,
              borderRadius: BorderRadius.circular(24.0),
              onTap: () => _onTap(v, isNew),
              child: HoverBuilder(
                builder: (context, hovered) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: UnderlineText(
                    text: v.lemma,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14.0,
                    ),
                    underlineColor: TokenRenderingUtil.underlineColor(
                      Theme.of(context).colorScheme.primary.withAlpha(200),
                      isNew: isNew,
                      selected: _selectedVocab == v,
                      hovered: hovered,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _WordCardWrapper extends StatefulWidget {
  final Vocab v;
  final String langCode;
  final String target;
  final VoidCallback onClose;

  const _WordCardWrapper({
    required this.v,
    required this.langCode,
    required this.target,
    required this.onClose,
  });

  @override
  State<_WordCardWrapper> createState() => _WordCardWrapperState();
}

class _WordCardWrapperState extends State<_WordCardWrapper> {
  @override
  void dispose() {
    widget.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WordZoomWidget(
      token: PangeaTokenText(
        content: widget.v.lemma,
        length: widget.v.lemma.characters.length,
        offset: 0,
      ),
      construct: ConstructIdentifier(
        lemma: widget.v.lemma,
        type: ConstructTypeEnum.vocab,
        category: widget.v.pos,
      ),
      langCode: widget.langCode,
      onClose: () {
        MatrixState.pAnyState.closeOverlay(widget.target);
        widget.onClose();
      },
      onDismissNewWordOverlay: () {
        if (mounted) setState(() {});
      },
    );
  }
}
