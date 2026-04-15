import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_details_row.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/tokens/collectable_tokens_mixin.dart';
import 'package:fluffychat/pangea/tokens/token_rendering_util.dart';
import 'package:fluffychat/pangea/tokens/tokens_util.dart';
import 'package:fluffychat/pangea/tokens/underline_text_widget.dart';
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
    return Column(
      spacing: 8.0,
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        ActivitySessionDetailsRow(
          icon: Symbols.dictionary,
          iconSize: 16.0,
          child: Text(
            L10n.of(context).suggestedVocab,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        usedVocab == null
            ? _VocabChips(
                vocab: vocab,
                targetId: targetId,
                langCode: langCode,
                usedVocab: const {},
                activityLangCode: activityLangCode,
              )
            : ValueListenableBuilder(
                valueListenable: usedVocab!,
                builder: (context, used, _) => _VocabChips(
                  vocab: vocab,
                  targetId: targetId,
                  langCode: langCode,
                  usedVocab: used,
                  activityLangCode: activityLangCode,
                ),
              ),
      ],
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

class _VocabChipsState extends State<_VocabChips> with CollectableTokensMixin {
  Vocab? _selectedVocab;
  late Set<PangeaTokenText> _newTokens;
  static const String _newTokensCacheKey = "activity_tokens";

  @override
  void initState() {
    super.initState();
    _computeNewTokens();
  }

  @override
  void didUpdateWidget(covariant _VocabChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vocab != widget.vocab ||
        oldWidget.activityLangCode != widget.activityLangCode) {
      _computeNewTokens();
    }
  }

  @override
  void dispose() {
    TokensUtil.instance.clearNewTokenCache();
    super.dispose();
  }

  String _vocabKey(Vocab v) => "${widget.targetId}-${v.lemma}";

  void _computeNewTokens() {
    _newTokens = TokensUtil.instance.getNewTokens(
      _newTokensCacheKey,
      widget.vocab.map((v) => v.asToken()).toList(),
      widget.activityLangCode,
    );
  }

  void _selectVocab(Vocab vocab, {bool isNew = false}) {
    setState(() => _selectedVocab = vocab);
    if (isNew) _onSelectNewVocab(vocab);
    _showWordCard(vocab);
  }

  Future<void> _onSelectNewVocab(Vocab vocab) async {
    final token = vocab.asToken();
    await collectToken(
      token: token,
      tokenCacheKey: _newTokensCacheKey,
      targetId: widget.targetId,
      langCode: widget.langCode,
    );
    _computeNewTokens();
  }

  void _showWordCard(Vocab vocab) {
    final target = _vocabKey(vocab);
    OverlayUtil.showPositionedCard(
      overlayKey: target,
      context: context,
      cardToShow: _WordCardWrapper(
        v: vocab,
        langCode: widget.langCode,
        target: target,
        onClose: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedVocab = null);
          });
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
    final newTokens = _newTokens;
    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      children: [
        ...widget.vocab.map((v) {
          final isNew = newTokens.any(
            (t) => t.content.toLowerCase() == v.lemma.toLowerCase(),
          );

          return _VocabChip(
            v: v,
            isUsed: widget.usedVocab.contains(v.lemma.toLowerCase()),
            isNew: isNew,
            isSelected: _selectedVocab == v,
            onTap: () => _selectVocab(v, isNew: isNew),
            target: _vocabKey(v),
          );
        }),
      ],
    );
  }
}

class _VocabChip extends StatelessWidget {
  final Vocab v;
  final bool isUsed;
  final bool isNew;
  final bool isSelected;
  final VoidCallback onTap;
  final String target;

  const _VocabChip({
    required this.v,
    required this.isUsed,
    required this.isNew,
    required this.isSelected,
    required this.onTap,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final linkAndKey = MatrixState.pAnyState.layerLinkAndKey(target);

    final color = isUsed
        ? Color.alphaBlend(
            Theme.of(context).colorScheme.surface.withAlpha(150),
            AppConfig.gold,
          )
        : Theme.of(context).colorScheme.primary.withAlpha(20);

    return CompositedTransformTarget(
      link: linkAndKey.link,
      child: InkWell(
        key: linkAndKey.key,
        borderRadius: BorderRadius.circular(24.0),
        onTap: onTap,
        child: HoverBuilder(
          builder: (context, hovered) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: UnderlineText(
              text: v.lemma,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
              underlineColor: TokenRenderingUtil.underlineColor(
                Theme.of(context).colorScheme.primary.withAlpha(200),
                isNew: isNew,
                selected: isSelected,
                hovered: hovered,
              ),
            ),
          ),
        ),
      ),
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
      pos: widget.v.pos,
      onClose: () {
        MatrixState.pAnyState.closeOverlay(widget.target);
        widget.onClose();
      },
    );
  }
}
