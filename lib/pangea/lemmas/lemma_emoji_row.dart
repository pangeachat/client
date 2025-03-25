import 'dart:developer';
import 'dart:math';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/app_emojis.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/word_zoom_activity_button.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LemmaEmojiRow extends StatefulWidget {
  final ConstructIdentifier cId;
  final VoidCallback? onTapOverride;
  final bool isSelected;
  final bool shouldShowEmojis;

  /// if a setState is defined then we're in a context where
  /// we allow removing an emoji
  /// later we'll probably want to allow this everywhere
  final void Function()? emojiSetCallback;

  const LemmaEmojiRow({
    super.key,
    required this.cId,
    required this.onTapOverride,
    required this.isSelected,
    required this.shouldShowEmojis,
    this.emojiSetCallback,
  });

  @override
  LemmaEmojiRowState createState() => LemmaEmojiRowState();
}

class LemmaEmojiRowState extends State<LemmaEmojiRow> {
  String? displayEmoji;

  @override
  void initState() {
    super.initState();
    displayEmoji = widget.cId.userSetEmoji.firstOrNull;
  }

  @override
  didUpdateWidget(LemmaEmojiRow oldWidget) {
    if (oldWidget.isSelected != widget.isSelected ||
        widget.cId.userSetEmoji != oldWidget.cId.userSetEmoji) {
      setState(() => displayEmoji = widget.cId.userSetEmoji.firstOrNull);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    MatrixState.pAnyState.disposeByWidgetKey(widget.cId.string);
    super.dispose();
  }

  void openEmojiSetOverlay() async {
    List<String> emojiChoices = [];
    try {
      final info = await widget.cId.getLemmaInfo();
      emojiChoices = info.emoji;
    } catch (e, s) {
      for (int i = 0; i < 3; i++) {
        emojiChoices
            .add(AppEmojis.emojis[Random().nextInt(AppEmojis.emojis.length)]);
      }
      debugger(when: kDebugMode);
      ErrorHandler.logError(data: widget.cId.toJson(), e: e, s: s);
    }

    try {
      OverlayUtil.showOverlay(
        context: context,
        child: EmojiEditOverlay(
          cId: widget.cId,
          onSelectEmoji: setEmoji,
          emojis: emojiChoices,
        ),
        transformTargetId: widget.cId.string,
        backDropToDismiss: true,
        blurBackground: false,
        borderColor: Theme.of(context).colorScheme.primary,
        closePrevOverlay: false,
      );
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(data: widget.cId.toJson(), e: e, s: s);
    }
  }

  Future<void> setEmoji(String emoji) async {
    try {
      displayEmoji = emoji;

      widget.cId
          .setUserLemmaInfo(
        UserSetLemmaInfo(
          emojis: [emoji],
        ),
      )
          .catchError((e, s) {
        debugger(when: kDebugMode);
        ErrorHandler.logError(data: widget.cId.toJson(), e: e, s: s);
      });

      MatrixState.pAnyState.closeOverlay();

      widget.emojiSetCallback?.call();

      setState(() {});
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(data: widget.cId.toJson(), e: e, s: s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: MatrixState.pAnyState
          .layerLinkAndKey(
            widget.cId.string,
          )
          .link,
      child: Container(
        key: MatrixState.pAnyState
            .layerLinkAndKey(
              widget.cId.string,
            )
            .key,
        height: 50,
        width: 50,
        alignment: Alignment.center,
        child: displayEmoji != null && widget.shouldShowEmojis
            ? InkWell(
                hoverColor: Theme.of(context).colorScheme.primary.withAlpha(50),
                onTap: widget.onTapOverride ?? openEmojiSetOverlay,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    displayEmoji!,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              )
            : WordZoomActivityButton(
                icon: Icon(
                  Icons.add_reaction_outlined,
                  color: widget.isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                isSelected: widget.isSelected,
                onPressed: widget.onTapOverride ?? openEmojiSetOverlay,
                opacity: widget.isSelected ? 1 : 0.4,
                tooltip: MessageMode.wordEmoji.title(context),
              ),
      ),
    );
  }
}

class EmojiEditOverlay extends StatelessWidget {
  final Function(String) onSelectEmoji;
  final ConstructIdentifier cId;
  final List<String> emojis;

  const EmojiEditOverlay({
    super.key,
    required this.onSelectEmoji,
    required this.cId,
    required this.emojis,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        padding: const EdgeInsets.all(8),
        height: 70,
        width: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(50),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: emojis
                .map(
                  (emoji) => EmojiChoiceItem(
                    emoji: emoji,
                    onSelectEmoji: onSelectEmoji,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class EmojiChoiceItem extends StatefulWidget {
  final String emoji;
  final Function(String) onSelectEmoji;

  const EmojiChoiceItem({
    super.key,
    required this.emoji,
    required this.onSelectEmoji,
  });

  @override
  EmojiChoiceItemState createState() => EmojiChoiceItemState();
}

class EmojiChoiceItemState extends State<EmojiChoiceItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          debugPrint('Selected emoji: ${widget.emoji}');
          if (!mounted) {
            return;
          }
          widget.onSelectEmoji(widget.emoji);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered
                ? Theme.of(context).colorScheme.primary.withAlpha(50)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          ),
          child: Text(
            widget.emoji,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ),
    );
  }
}
