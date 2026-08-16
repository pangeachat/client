/// The listening categories the dosage lane tracks, and the coverage categories
/// a build declares.
///
/// The two are deliberately different types. A playback event is always one of
/// the three LISTENING categories; `voiceSend` is a coverage category only —
/// speaking's magnitude is derived server-side from the `m.audio` event, so
/// there is no client-side speaking playback event for it to label. Splitting
/// the enums makes "emit a listening event tagged voiceSend" unrepresentable
/// rather than merely wrong.
///
/// Design: docs/research/104-speaking-listening-minutes-v2.md, §1 and D-V2-9.
library;

/// A category of listening, decided by WHO INITIATED THE PLAYBACK (D-V2-3) —
/// never by who paid for it and never by which widget rendered it.
///
/// The category is a CONSTANT at each emit site, never a runtime discriminator
/// (D-V2-1). The shared playback components cannot tell these apart: one
/// `AudioPlayerWidget` serves the timeline, the practice card and the analytics
/// practice widget, and one `TtsController.tryToSpeak` serves automatic
/// read-aloud, word taps and choice taps. Only the CALLER knows which kind of
/// listening it is asking for, so only the caller may name it.
enum DosageListeningCategory {
  /// The learner played a voice message somebody else sent — a peer or the bot.
  /// Emitted from the timeline's `AudioPlayerWidget` call site only.
  peer('peer'),

  /// A received message was read aloud automatically, with no learner action.
  /// Category 2 even when it reaches the paid backend in voice-reply mode
  /// (D-V2-3): it was not initiated by the learner tapping anything.
  autoRead('auto_read'),

  /// The learner tapped the speaker button on a message in conversation.
  tapRead('tap_read');

  const DosageListeningCategory(this.wireName);

  /// The value carried in the signal's `category` field.
  final String wireName;

  /// The coverage category whose declaration makes this counter servable.
  DosageCoverageCategory get coverage => switch (this) {
    DosageListeningCategory.peer => DosageCoverageCategory.peer,
    DosageListeningCategory.autoRead => DosageCoverageCategory.autoRead,
    DosageListeningCategory.tapRead => DosageCoverageCategory.tapRead,
  };

  /// The category for a TIMELINE audio message, or null when this playback is
  /// not listening at all.
  ///
  /// Category 1 is "the learner heard audio somebody ELSE sent", so replaying
  /// one's own voice message is not listening and emits nothing. Bot audio IS
  /// somebody else — the bot still sends `m.audio`, and a bot-mediated course is
  /// where most received audio actually lives.
  ///
  /// Pure, so the one discriminator in the whole feature that is not a hard-coded
  /// constant can be tested without a player, a timeline or a logged-in client.
  /// It is sound ONLY at the timeline call site, where the sender is a real
  /// Matrix sender; the practice widgets pass the learner's own mxid for audio
  /// the learner did not send, which is exactly why they are out of scope and
  /// why this must never be moved inside the shared player widget.
  static DosageListeningCategory? forTimelineAudio({
    required String senderId,
    required String? ownUserId,
  }) {
    // No account resolved: the observation cannot be attributed to anyone, and
    // guessing is worse than losing it.
    if (ownUserId == null || ownUserId.isEmpty) return null;
    if (senderId.isEmpty) return null;
    return senderId == ownUserId ? null : DosageListeningCategory.peer;
  }
}

/// A category of instrumentation this build declares it is running (D-V2-9).
///
/// Coverage is what converts "no signal" into "zero" rather than "unknown", so
/// a category that is NOT declared is uncovered and its counter is withheld.
/// There are four, not three: `voiceSend` covers the `onVoiceMessageSend`
/// envelope and therefore `speakingMinutes` and `voiceMessagesSent` (D-V2-15).
/// Speaking's MEASUREMENT is server-side, but the server never learns a voice
/// message exists without a client-originated row, so its DENOMINATOR is
/// client-side and needs the same declaration.
enum DosageCoverageCategory {
  peer('peer'),
  autoRead('auto_read'),
  tapRead('tap_read'),
  voiceSend('voice_send');

  const DosageCoverageCategory(this.wireName);

  /// The value carried in the declaration's `category` field.
  final String wireName;
}
