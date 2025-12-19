import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_misc/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_highlight_emoji_row.dart';
import 'package:fluffychat/widgets/matrix.dart';

class VocabDetailsEmojiSelector extends StatefulWidget {
  final ConstructIdentifier constructId;

  const VocabDetailsEmojiSelector(
    this.constructId, {
    super.key,
  });

  @override
  State<VocabDetailsEmojiSelector> createState() =>
      VocabDetailsEmojiSelectorState();
}

class VocabDetailsEmojiSelectorState extends State<VocabDetailsEmojiSelector>
    with LemmaEmojiSetter {
  String? selectedEmoji;

  @override
  void initState() {
    super.initState();
    _setInitialEmoji();
  }

  @override
  void didUpdateWidget(covariant VocabDetailsEmojiSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.constructId != widget.constructId) {
      _setInitialEmoji();
    }
  }

  void _setInitialEmoji() {
    setState(
      () {
        selectedEmoji = widget.constructId.userLemmaInfo.emojis?.firstOrNull;
      },
    );
  }

  Future<void> _setEmoji(String emoji) async {
    setState(() => selectedEmoji = emoji);
    await setLemmaEmoji(
      widget.constructId,
      emoji,
      "emoji-choice-item-$emoji-${widget.constructId.lemma}",
    );
    showLemmaEmojiSnackbar(context, widget.constructId, emoji);
  }

  @override
  Widget build(BuildContext context) {
    return LemmaHighlightEmojiRow(
      cId: widget.constructId,
      langCode: MatrixState.pangeaController.userController.userL2Code!,
      emoji: selectedEmoji,
      onEmojiSelected: _setEmoji,
      messageInfo: const {},
    );
  }
}
