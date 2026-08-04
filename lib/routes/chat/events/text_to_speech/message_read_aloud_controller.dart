import 'dart:async';

import 'package:matrix/matrix.dart';

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
/// Decides which arriving messages qualify; [ReadAloudQueue] owns the
/// one-at-a-time playback scheduling.
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
      canPlay: () => _isEnabled && !isSuppressed(),
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

  void _onSync(SyncUpdate update) {
    if (!_isEnabled) return;
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
    if (event.senderId == room.client.userID) return false;
    if (event.type != EventTypes.Message) return false;
    if (event.messageType != MessageTypes.Text) return false;
    return !event.redacted && event.status.isSynced;
  }

  bool _isInTargetLanguage(PangeaMessageEvent message) {
    final targetLangCode =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;
    if (targetLangCode == null) return false;
    final messageLangCode = message.originalSent?.langCode.split('-').first;
    return messageLangCode == targetLangCode;
  }

  /// Backend TTS is disallowed here: read-aloud fires on every eligible
  /// incoming message, so its volume is driven by how much others type rather
  /// than by the learner. Without a known-good device voice, nothing plays.
  Future<void> _speak(PangeaMessageEvent message) => TtsController.tryToSpeak(
    message.messageDisplayText,
    langCode: message.messageDisplayLangCode,
    useCase: TtsUseCase.incomingMessage,
    allowChoreoPlay: false,
  );
}
