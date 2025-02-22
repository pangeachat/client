// EmojiViewWidget replaces regular EmojiPicker
// When no word is selected
// Show a list of LanguageLearningEmojiWidgets. This list is produced by the pangea_message_event_model.dart.
// For each token in the messageDisplayTokens (if null then regular emojis):
// If save_vocab, show
// 1) token.xpEmoji for new words that you haven't chosen an emoji for OR
// 2) once you’ve selected an emoji, the seed grows into a little sprout before being covered by the selected emoji with a popping sound OR
// 3) the emoji you selected previously.
// Else show
// token.text.content.
// This helps remind the user to interpret the message just via the images. It helps remind them what it means in visuals rather than words.
// It mirrors the green highlights which enhances accessibility.
// When a word is selected,
// The bottom bar shows the selection of emojis that you can choose for that word.
// Only if the messageDisplayTokens are null do show the regular emojis. They suck anyway.

class PangeaEmojiMeaningView extends StatelessWidget {
  final PangeaMessageEvent messageEvent;
  final PangeaToken? selectedToken;

  PangeaEmojiMeaningView({
    required this.messageEvent,
    this.selectedToken,
  });

  @override
  Widget build(BuildContext context) {
    // Check if a word is selected
    if (selectedToken == null) {
      // No word is selected, show the list of LanguageLearningEmojiWidgets
      return Column(
        children: [
          // For each token in the messageDisplayTokens
          for (final token
              in messageEvent.messageDisplayRepresentation?.tokens ?? [])
            if (token.saveVocab)
              // Show token.xpEmoji for new words that you haven't chosen an emoji for
              // OR the emoji you selected previously
              LanguageLearningEmojiWidget(
                emoji: token.getEmoji() ?? token.xpEmoji,
                onTap: () {
                  // Handle emoji tap
                },
              )
            else
              // Else show token.text.content
              Text(token.text.content),
        ],
      );
    } else {
      // A word is selected, show the selection of emojis that you can choose for that word
      return BottomAppBar(
        child: Row(
          children: [
            // Show a list of emojis to choose from
            for (final emoji in getAvailableEmojisForToken(selectedToken))
              GestureDetector(
                onTap: () {
                  // Handle emoji selection
                  setEmojiForToken(selectedToken, emoji);
                },
                child: Text(emoji),
              ),
          ],
        ),
      );
    }
  }

  // Function to get available emojis for a token
  List<String> getAvailableEmojisForToken(token) {
    // Return a list of available emojis for the token
    return ['😀', '😁', '😂', '🤣', '😃'];
  }

  // Function to set emoji for a token
  void setEmojiForToken(PangeaToken? token, String emoji) {
    // Set the selected emoji for the token
    token?.setEmoji(emoji);
  }
}
