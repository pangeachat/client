import 'dart:developer';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_emojis.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_emoji_row.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';

class LemmmaHighlightEmojiRow extends StatefulWidget {
  final ConstructIdentifier cId;
  final VoidCallback? onTapOverride;
  final bool isSelected;
  final double? iconSize;

  final void Function()? emojiSetCallback;

  const LemmmaHighlightEmojiRow({
    super.key,
    required this.cId,
    required this.onTapOverride,
    required this.isSelected,
    this.emojiSetCallback,
    this.iconSize,
  });

  @override
  LemmmaHighlightEmojiRowState createState() => LemmmaHighlightEmojiRowState();
}

class LemmmaHighlightEmojiRowState extends State<LemmmaHighlightEmojiRow> {
  String? displayEmoji;
  List<String> emojiChoices = [];

  @override
  void initState() {
    super.initState();
    loadEmojiSet();
    displayEmoji = widget.cId.userSetEmoji.firstOrNull;
  }

  @override
  didUpdateWidget(LemmmaHighlightEmojiRow oldWidget) {
    if (oldWidget.isSelected != widget.isSelected ||
        widget.cId.userSetEmoji != oldWidget.cId.userSetEmoji) {
      setState(() => displayEmoji = widget.cId.userSetEmoji.firstOrNull);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void loadEmojiSet() async {
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

    // Trigger rebuild once emojis are loaded
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> setEmoji(String emoji) async {
    try {
      displayEmoji = emoji;

      await widget.cId.setUserLemmaInfo(
        UserSetLemmaInfo(
          emojis: [emoji],
        ),
      );

      if (mounted) {
        widget.emojiSetCallback?.call();
        setState(() {});
      }
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(data: widget.cId.toJson(), e: e, s: s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: EmojiEditOverlay(
        cId: widget.cId,
        onSelectEmoji: setEmoji,
        emojis: emojiChoices,
        displayEmoji: displayEmoji,
      ),
    );
  }
}
