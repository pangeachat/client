import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_misc/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_highlight_emoji_row.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaReactionPicker extends StatefulWidget {
  final Event? event;
  final ConstructIdentifier constructId;
  final Function(String)? onSetEmoji;
  final String langCode;

  const LemmaReactionPicker({
    super.key,
    required this.constructId,
    required this.onSetEmoji,
    required this.langCode,
    this.event,
  });

  @override
  State<LemmaReactionPicker> createState() => LemmaReactionPickerState();
}

class LemmaReactionPickerState extends State<LemmaReactionPicker>
    with LemmaEmojiSetter {
  String? _selectedEmoji;

  @override
  void initState() {
    super.initState();
    _setInitialEmoji();
  }

  @override
  void didUpdateWidget(covariant LemmaReactionPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.constructId != widget.constructId) {
      _setInitialEmoji();
    }
  }

  void _setInitialEmoji() {
    setState(
      () {
        _selectedEmoji = widget.constructId.userLemmaInfo.emojis?.firstOrNull;
      },
    );
  }

  Event? _sentReaction(String emoji) {
    final userSentEmojis = widget.event!
        .aggregatedEvents(
          widget.event!.room.timeline!,
          RelationshipTypes.reaction,
        )
        .where(
          (e) => e.senderId == Matrix.of(context).client.userID,
        );

    return userSentEmojis.firstWhereOrNull(
      (e) => e.content.tryGetMap('m.relates_to')?['key'] == emoji,
    );
  }

  Future<void> _setEmoji(String emoji) async {
    setState(() => _selectedEmoji = emoji);
    widget.onSetEmoji?.call(emoji);

    await setLemmaEmoji(
      widget.constructId,
      emoji,
      "emoji-choice-item-$emoji-${widget.constructId.lemma}",
    );

    if (mounted) {
      showLemmaEmojiSnackbar(context, widget.constructId, emoji);
    }
  }

  Future<void> _sendOrRedactReaction(String emoji) async {
    if (widget.event?.room.timeline == null) return;

    try {
      final reactionEvent = _sentReaction(emoji);
      if (reactionEvent != null) {
        await reactionEvent.redactEvent();
        return;
      }

      await widget.event!.room.sendReaction(
        widget.event!.eventId,
        emoji,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'emoji': emoji,
          'eventId': widget.event?.eventId,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LemmaHighlightEmojiRow(
      cId: widget.constructId,
      langCode: widget.langCode,
      onEmojiSelected: (emoji) => emoji != _selectedEmoji
          ? _setEmoji(emoji)
          : _sendOrRedactReaction(emoji),
      emoji: _selectedEmoji,
      messageInfo: widget.event?.content ?? {},
      selectedEmojiBadge: widget.event != null &&
              _selectedEmoji != null &&
              _sentReaction(_selectedEmoji!) == null
          ? const Icon(
              Icons.add_reaction,
              size: 12.0,
            )
          : null,
    );
  }
}
