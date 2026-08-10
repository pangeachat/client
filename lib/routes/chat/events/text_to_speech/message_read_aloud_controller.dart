import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
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
/// Gated by [ToolSetting.audioIncomingMessages]. [voiceMode] does not change
/// *whether* a message is read, only whether the bot's reply to a voice message
/// may reach backend TTS instead of staying silent. See "Voice mode" in the
/// design doc.
///
/// Decides which arriving messages qualify; [ReadAloudQueue] owns the
/// one-at-a-time playback scheduling.
///
/// The same setting also reads a message the learner deliberately taps, via
/// [readSelectedMessage] — one feature reached two ways, not two features.
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

  bool get _isEnabled => MatrixState.pangeaController.userController
      .isToolEnabled(ToolSetting.audioIncomingMessages);

  /// Whether this is the bot answering a voice message the learner just sent.
  ///
  /// Such a reply is read aloud whether or not `audioIncomingMessages` is on,
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
  bool get _canReadSomething => _isEnabled || voiceMode;

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
    if (!_isReadableContent(event)) return false;
    return qualifies(
      settingEnabled: _isEnabled,
      voiceReply: _isVoiceReply(event),
    );
  }

  /// Whether the event is the kind of message read-aloud can speak at all,
  /// independent of what prompted the read. Shared by arrival and by
  /// [readSelectedMessage] so a tap can never read something an arrival
  /// wouldn't.
  bool _isReadableContent(Event event) {
    if (event.senderId == room.client.userID) return false;
    if (event.type != EventTypes.Message) return false;
    if (event.messageType != MessageTypes.Text) return false;
    return !event.redacted && event.status.isSynced;
  }

  /// Whether opening the toolbar over a message should speak that message.
  ///
  /// Gated on the same toggle as an arriving message — no second setting, this
  /// is the same feature reached a second way. A tutorial that opens the
  /// toolbar on the learner's behalf speaks its own instruction over it, and a
  /// tapped token plays the word instead: the more specific request wins.
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
  /// Same toggle and the same qualifying conditions as an arriving message,
  /// minus the arrived-while-open rule: that rule stops a backlog playing at
  /// once, and a message the learner picked out and tapped is on screen and
  /// asked for by definition.
  ///
  /// Device-only and gated: voice mode's backend exception does not extend
  /// here, because a tap is not a spoken exchange.
  ///
  /// Design — "Reading on select":
  /// client/.github/instructions/message-read-aloud.instructions.md
  Future<void> readSelectedMessage(
    PangeaMessageEvent message, {
    required bool isTutorial,
    required bool tokenSelected,
  }) {
    if (!readsOnSelect(
      settingEnabled: _isEnabled,
      isTutorial: isTutorial,
      tokenSelected: tokenSelected,
    )) {
      return Future.value();
    }
    if (!_isReadableContent(message.event)) return Future.value();
    if (!_isInTargetLanguage(message)) return Future.value();

    // Ends the automatic read first. Selecting a message clears the queue
    // anyway, but that happens once the overlay registers the selection — after
    // this call — and would otherwise stop the audio being started here.
    stopAndClear();

    return TtsController.tryToSpeak(
      message.messageDisplayText,
      langCode: message.messageDisplayLangCode,
      useCase: TtsUseCase.incomingMessage,
      allowChoreoPlay: false,
    );
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
  Future<void> _speak(PangeaMessageEvent message) {
    final voiceReply = _isVoiceReply(message.event);
    return TtsController.tryToSpeak(
      message.messageDisplayText,
      langCode: message.messageDisplayLangCode,
      useCase: voiceReply ? TtsUseCase.voiceReply : TtsUseCase.incomingMessage,
      allowChoreoPlay: voiceReply,
    );
  }
}
