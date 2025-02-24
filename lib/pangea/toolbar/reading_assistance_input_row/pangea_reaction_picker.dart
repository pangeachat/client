import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/analytics_misc/message_analytics_controller.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/emoji_choice_item.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/practice_activity_card.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'message_emoji_choice_row.dart';

// the actionBar presents a series of easy choices for the user to make
// to help them learn the words in the message

// there is a total possible points via these interaction and you can see your score at the end
// you're awarded a seed, sprout or flower emoji as a result of how well you do
//

// Important note: Th content in the toolBarContent shows 1) content for the word/message as selected 2) navigation between the different modes
// Just in case the user wants to progress some other way through the information
enum ReadingAssistanceActionBarModeEnum {
  //full selection of emojis that have been unlocked, one for each token in the message
  // allows the learner to send that emoji to the message with a longpress or double-tap
  // or they can navigate to the word views with a single tap
  emojiMessageChoice,

  // after selecting a seed emoji, you are presented with a choice of 4-5 relevant emojis to mark it with
  // and choosing the emoji for the word, you get a seed (not XP)
  // after getting the seed, the selection goes back to the whole message
  emojiWordChoice,

  // after selecting an emoji, you are presented with a choice of 4-5 meanings for the word
  // and choosing the meaning for the word, you get from 1-5 total XP depending on your choices
  meaning,

  // for languages that have a different script, you can choose to listen to the word being pronounced
  // and choosing which word you hear
  // distractors are selected for semantic similarity rather than phonetic similarity
  // this puts less burden on the tts system to be super precise
  wordListening,

  // at this point you get a hidden word listening activity
  messageListening,

  // for languages that have a different script, you can choose to listen to the word being pronounced
  // and then pronouncing it yourself. you can record as much as you want
  // the goal is to replace the shitty tts with your own voice eventually
  pronunciation,

  // now they get a part of speech activity and the rest of the morphs
  // selecting between the emojis, with their names
  pos,
  otherMorphs,

  // if you want, you can spend a star to get the message translated immediately
  messageMeaning
}

class ReadingAssistanceActionBar extends StatelessWidget {
  final ChatController controller;
  final MessageOverlayController? overlayController;

  const ReadingAssistanceActionBar(
    this.controller,
    this.overlayController, {
    super.key,
  });

  PangeaToken? get token => overlayController?.selectedToken;

  /// If not save_vocab, show token.text.content
  /// Otherwise, show:
  /// 1) token.xpEmoji for new words that you haven't chosen an emoji for OR
  /// - once you’ve selected an emoji, the seed grows into a little sprout before being covered by the selected emoji with a popping sound
  /// 2) the emoji you selected previously.
  Widget emojiView(PangeaToken token) {
    if (!token.lemma.saveVocab) {
      return EmojiChoiceItem(
        content: token.text.content,
        onTap: () => overlayController!.onClickOverlayMessageToken(token),
        // onTap: controller.sendEmojiAction,
        isSelected: false,
      );
    }

    final emoji = token.getEmoji();

    if (emoji == null) {
      return Opacity(
        opacity: 0.1,
        child: EmojiChoiceItem(
          content: token.xpEmoji,
          onTap: () => overlayController!.onClickOverlayMessageToken(token),
          // onTap: controller.sendEmojiAction,
          isSelected: false,
        ),
      );
    }

    // emoji has been selected
    return EmojiChoiceItem(
      content: emoji,
      onTap: () => controller.sendEmojiAction(emoji),
      isSelected: false,
    );
  }

  Iterable<Event> get allReactionEvents => controller.selectedEvents.first
      .aggregatedEvents(
        controller.timeline!,
        RelationshipTypes.reaction,
      )
      .where(
        (event) =>
            event.senderId == event.room.client.userID &&
            event.type == 'm.reaction',
      );

  List<Widget> get messageEmojiList =>
      overlayController
          ?.pangeaMessageEvent?.messageDisplayRepresentation?.tokens
          ?.where((token) => token.lemma.saveVocab)
          .map((token) => emojiView(token))
          .toList() ??
      [];

  @override
  Widget build(BuildContext context) {
    if (controller.showEmojiPicker) return const SizedBox.shrink();
    final display = controller.editEvent == null &&
        controller.replyEvent == null &&
        controller.room.canSendDefaultMessages &&
        controller.selectedEvents.isNotEmpty;

    if (!display) {
      return const SizedBox.shrink();
    }

    return Flexible(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        // @ggurdin - redundant no?
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: overlayController?.selectedToken == null
                  ? MessageEmojiChoiceRow(
                      tokens: overlayController?.pangeaMessageEvent
                              ?.messageDisplayRepresentation?.tokens ??
                          [],
                      controller: controller,
                      overlayController: overlayController,
                    )
                  : PracticeActivityCard(
                      pangeaMessageEvent:
                          overlayController!.pangeaMessageEvent!,
                      targetTokensAndActivityType: TargetTokensAndActivityType(
                        tokens: [overlayController!.selectedToken!],
                        activityType: ActivityTypeEnum.emoji,
                      ),
                      overlayController: overlayController!,
                      location: AnalyticsUpdateOrigin.inputBar,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
