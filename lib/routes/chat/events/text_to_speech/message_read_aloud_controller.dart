import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/read_aloud_queue.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Reads incoming target-language messages aloud with device text-to-speech
/// while the learner has the chat open, so a conversation doubles as listening
/// practice.
///
/// Gated by [ToolSetting.audioOnNewMessage]. [voiceMode] does not change
/// *whether* a message is read, only whether the bot's reply to a voice message
/// may reach backend TTS instead of staying silent. See "Voice mode" in the
/// design doc.
///
/// Decides which arriving messages qualify; [ReadAloudQueue] owns the
/// one-at-a-time playback scheduling.
///
/// A message the learner deliberately taps is read via [readSelectedMessage],
/// behind its own toggle, [ToolSetting.audioOnMessageClick].
///
/// Design — what qualifies to be read, the single waiting slot, and the stop
/// conditions: client/.github/instructions/message-read-aloud.instructions.md
class MessageReadAloudController {
  MessageReadAloudController({
    required this.room,
    required this.currentTimeline,
    required this.isSuppressed,
  }) {
    _queue = ReadAloudQueue<PangeaMessageEvent>(
      speak: _speak,
      canPlay: () => _canReadSomething && !isSuppressed(),
    );
  }

  final Room room;

  /// The room's live timeline, needed to resolve a message's language.
  final Timeline? Function() currentTimeline;

  /// Whether the chat is in a state that silences read-aloud — a message is
  /// selected, or the learner is part-way through a draft. Read live so every
  /// route into those states counts, not just the ones that call [stopAndClear].
  final bool Function() isSuppressed;

  late final ReadAloudQueue<PangeaMessageEvent> _queue;

  StreamSubscription<SyncUpdate>? _syncSubscription;
  DateTime? _openedAt;

  /// Whether the learner is in a spoken exchange: set when they send a voice
  /// note, cleared when they send text. This is the rule the bot used to apply
  /// server-side — it replied with audio when the trigger was a voice note —
  /// relocated to the only process that can see the device's voices, the
  /// learner's subscription and their settings.
  ///
  /// Deliberately session state rather than a predicate over the timeline.
  /// A derived version would misfire three ways: errored events are pinned to
  /// the front of `Timeline.events`, so a voice note that fails to upload would
  /// hold the mode open for the session; edits are themselves `m.room.message`
  /// events in that list, so editing any older message would silently flip it;
  /// and history pagination can page in a week-old voice note and flip it with
  /// no user action at all.
  bool voiceMode = false;

  void start() {
    _openedAt = DateTime.now();
    _syncSubscription?.cancel();
    _syncSubscription = room.client.onSync.stream.listen(_onSync);
  }

  void dispose() {
    _syncSubscription?.cancel();
    _syncSubscription = null;
    stopAndClear();
  }

  /// Stops playback in progress and drops the waiting message. Called when the
  /// learner selects a message or begins a draft.
  void stopAndClear() {
    final wasSpeaking = _queue.isSpeaking;
    _queue.clear();
    if (wasSpeaking) TtsController.forceStop();
  }

  bool get _isAutoReadEnabled => MatrixState.pangeaController.userController
      .isToolEnabled(ToolSetting.audioOnNewMessage);

  bool get _isClickReadEnabled => MatrixState.pangeaController.userController
      .isToolEnabled(ToolSetting.audioOnMessageClick);

  /// Whether this is the bot answering a voice message the learner just sent.
  ///
  /// Such a reply is read aloud whether or not `audioOnNewMessage` is on,
  /// because the learner asked for it by speaking — see [TtsUseCase.voiceReply].
  /// Restricted to the bot so that one voice message in a busy activity room
  /// cannot start speaking every other participant.
  ///
  /// Pure so the decision is unit-testable without Matrix, TTS or app state.
  @visibleForTesting
  static bool isVoiceReply({
    required bool voiceMode,
    required bool senderIsBot,
  }) => voiceMode && senderIsBot;

  /// Whether a message qualifies to be read at all: either the learner opted
  /// into unprompted read-aloud, or this is a voice reply.
  @visibleForTesting
  static bool qualifies({
    required bool settingEnabled,
    required bool voiceReply,
  }) => settingEnabled || voiceReply;

  bool _isVoiceReply(Event event) => isVoiceReply(
    voiceMode: voiceMode,
    senderIsBot: event.senderId == BotName.byEnvironment,
  );

  /// Live, so the queue re-reads it before draining its waiting slot: sending a
  /// text message ends voice mode and the pending reply is dropped.
  bool get _canReadSomething => _isAutoReadEnabled || voiceMode;

  void _onSync(SyncUpdate update) {
    if (!_canReadSomething) return;
    final timeline = currentTimeline();
    final matrixEvents = update.rooms?.join?[room.id]?.timeline?.events;
    if (timeline == null || matrixEvents == null) return;

    for (final matrixEvent in matrixEvents) {
      final event = Event.fromMatrixEvent(matrixEvent, room);
      if (!_isReadableMessage(event)) continue;

      final message = PangeaMessageEvent(
        event: event,
        timeline: timeline,
        ownMessage: false,
      );
      if (!_isInTargetLanguage(message)) continue;
      _queue.add(message);
    }
  }

  bool _isReadableMessage(Event event) {
    final openedAt = _openedAt;
    if (openedAt == null) return false;

    // Nothing retroactive: a backlog of unheard messages would be noise rather
    // than practice, so only what arrives after the chat opens is read.
    if (!event.originServerTs.isAfter(openedAt)) return false;
    // Received only: the learner's own sends (including echoes from another
    // device) offer no listening practice unprompted. A click is different —
    // see readSelectedMessage.
    if (event.senderId == room.client.userID) return false;
    if (!_isReadableContent(event)) return false;
    return qualifies(
      settingEnabled: _isAutoReadEnabled,
      voiceReply: _isVoiceReply(event),
    );
  }

  /// Whether the event is the kind of message read-aloud can speak at all,
  /// independent of what prompted the read. Shared by arrival and by
  /// [readSelectedMessage].
  bool _isReadableContent(Event event) {
    if (event.type != EventTypes.Message) return false;
    if (event.messageType != MessageTypes.Text) return false;
    return !event.redacted && event.status.isSynced;
  }

  /// Whether opening the toolbar over a message should speak that message.
  ///
  /// Gated on [ToolSetting.audioOnMessageClick], independent of the
  /// new-message toggle. A tutorial that opens the toolbar on the learner's
  /// behalf speaks its own instruction over it, and a tapped token plays the
  /// word instead: the more specific request wins.
  ///
  /// Pure so the decision is unit-testable without Matrix, TTS or app state.
  @visibleForTesting
  static bool readsOnSelect({
    required bool settingEnabled,
    required bool isTutorial,
    required bool tokenSelected,
  }) => settingEnabled && !isTutorial && !tokenSelected;

  /// Reads a message the learner deliberately selected.
  ///
  /// Same qualifying conditions as an arriving message, minus two: the
  /// arrived-while-open rule (it stops a backlog playing at once, and a tapped
  /// message is on screen and asked for by definition) and the received-only
  /// rule — the learner's own L2 messages are read on click too, since a click
  /// asks to hear that message, whoever sent it (#8264).
  ///
  /// Device-only and gated: voice mode's backend exception does not extend
  /// here, because a tap is not a spoken exchange.
  ///
  /// Design — "Reading on click":
  /// client/.github/instructions/message-read-aloud.instructions.md
  Future<void> readSelectedMessage(
    PangeaMessageEvent message, {
    required bool isTutorial,
    required bool tokenSelected,
  }) async {
    if (!readsOnSelect(
      settingEnabled: _isClickReadEnabled,
      isTutorial: isTutorial,
      tokenSelected: tokenSelected,
    )) {
      return;
    }
    if (!_isReadableContent(message.event)) return;
    if (!_isInTargetLanguage(message)) return;

    // Ends the automatic read first. Selecting a message clears the queue
    // anyway, but that happens once the overlay registers the selection — after
    // this call — and would otherwise stop the audio being started here.
    stopAndClear();

    // Listening category 4 (#104): TOOLBAR-OPEN read-aloud.
    //
    // Its own category, not folded into either neighbour. Not category 2: the
    // learner opened the toolbar, so this playback was initiated by them, and
    // category 2's entire meaning is "nobody asked". Not category 3 either: that
    // is the speaker button, a separate affordance on a different surface, fired
    // deliberately to hear a message again and routed to the paid backend voice.
    // This is device-only and comes free with selecting a message, so it is far
    // more frequent and means something else. Merging either way would give one
    // counter two meanings and make a teacher-visible number unreadable.
    //
    // The category is a constant HERE because `tryToSpeak` serves this, the
    // automatic read above, and every word and choice tap, and cannot tell them
    // apart.
    final probe = _listeningProbe(DosageListeningCategory.toolbarRead);
    try {
      await TtsController.tryToSpeak(
        message.messageDisplayText,
        langCode: message.messageDisplayLangCode,
        useCase: TtsUseCase.messageClick,
        allowChoreoPlay: false,
        // `allowChoreoPlay: false` with no known-good device voice returns near
        // instantly and still fires `onStop`, so the returned future cannot tell
        // silence from speech. This pair can: it brackets a route that was
        // actually asked to play, and only that.
        onPlaybackStarted: probe.started,
        onPlaybackAborted: probe.aborted,
      );
    } finally {
      probe.finish();
    }
  }

  bool _isInTargetLanguage(PangeaMessageEvent message) {
    final targetLangCode =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;
    if (targetLangCode == null) return false;
    final messageLangCode = message.correctedSent?.langCode.split('-').first;
    return messageLangCode == targetLangCode;
  }

  /// Setting-driven read-aloud is device-only and gated: it fires on every
  /// eligible incoming message, so its volume is driven by how much other people
  /// type, and without a known-good device voice nothing plays.
  ///
  /// A voice reply is the exception on both counts. It is ungated
  /// ([TtsUseCase.voiceReply]) because the learner asked for it by speaking, and
  /// it may reach backend TTS because device-only would mean total silence — no
  /// error, no indicator — wherever the device has no known-good voice for the
  /// L2 (Safari, desktop Chrome without a Google voice, Android without a
  /// high-quality voice). Both were true of the bot-generated audio this
  /// replaces, which always played and always cost a paid request.
  Future<void> _speak(PangeaMessageEvent message) async {
    final voiceReply = _isVoiceReply(message.event);

    // Listening category 2 (#104): AUTOMATIC read-aloud of a received message.
    //
    // Category 2 even in voice-reply mode, where this reaches the paid backend
    // voice. The categories split on who INITIATED the playback, not on who paid
    // for it — the learner tapped nothing here, the message simply arrived.
    // Naming the counters after cost would make them mean different things in
    // different modes.
    //
    // The room is threaded from here because [TtsController.tryToSpeak] takes
    // neither a room nor an event id and serves word and choice taps too; it
    // could not name the category or the room if it wanted to.
    final probe = _listeningProbe(DosageListeningCategory.autoRead);
    try {
      await TtsController.tryToSpeak(
        message.messageDisplayText,
        langCode: message.messageDisplayLangCode,
        useCase: voiceReply ? TtsUseCase.voiceReply : TtsUseCase.newMessage,
        allowChoreoPlay: voiceReply,
        // Fires only when a route is asked to play, so the silent exits — no
        // known-good device voice with the backend disallowed, tool setting
        // off, request superseded — measure nothing rather than banking a
        // near-zero interval for audio that never played.
        onPlaybackStarted: probe.started,
        // And whether a route DID play is only knowable after it was asked. A
        // backend attempt that fails and falls back to the device must not have
        // the failure, or the switch, counted as audio the learner heard.
        onPlaybackAborted: probe.aborted,
      );
    } finally {
      // In `finally` so a throw out of TTS still closes the measurement, and
      // AFTER the await so nothing here can delay speech. It emits nothing when
      // playback never started.
      probe.finish();
    }
  }

  /// One measurement of one `tryToSpeak` call, tagged with the category this
  /// controller's caller is asking for.
  ///
  /// The controller reads aloud for TWO different reasons and they are two
  /// different categories — see the call sites. The category is the only thing
  /// that differs, which is exactly why it is an argument here and a constant
  /// there, rather than something this method could decide for itself.
  DosageTtsListeningProbe _listeningProbe(DosageListeningCategory category) =>
      DosageTtsListeningProbe(
        category: category,
        roomId: room.id,
        userId: () => room.client.userID,
        accessToken: () => room.client.accessToken,
      );
}
