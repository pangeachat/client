/// What a tap on a tray choice does.
enum PracticeChoiceTap {
  /// No blank is chosen yet, so the choice has nothing to fill.
  ignore,

  /// Play the choice and highlight it, without answering.
  preview,

  /// Fill the chosen blank with this choice.
  answer,
}

/// Resolves a tap on a tray choice.
///
/// A choice the learner can read is answered on the first tap. An audio choice
/// has to be heard before it can be judged, so its first tap only plays it and
/// a second tap on the same choice answers. Dragging never routes through
/// here: a dragged choice carries its own blank.
class PracticeChoiceTapResolver {
  static PracticeChoiceTap resolve({
    required bool hasSelectedSlot,
    required bool isAudioChoice,
    required bool isSelectedChoice,
  }) {
    if (!hasSelectedSlot) return PracticeChoiceTap.ignore;
    if (isAudioChoice && !isSelectedChoice) return PracticeChoiceTap.preview;
    return PracticeChoiceTap.answer;
  }
}
