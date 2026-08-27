import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';
import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/extensions/room_member_change_extension.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/text_to_speech_response_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_audio_card.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

extension PangeaEvent on Event {
  V getPangeaContent<V>() {
    final Map<String, dynamic>? json = content[type] as Map<String, dynamic>?;

    if (json == null) {
      debugger(when: kDebugMode);
      throw Exception("$type event with null content $eventId");
    }

    //PTODO - how does this work? abstract class?
    // return V.fromJson(json);

    switch (type) {
      case PangeaEventTypes.tokens:
        return PangeaMessageTokens.fromJson(json) as V;
      case PangeaEventTypes.representation:
        return PangeaRepresentation.fromJson(json) as V;
      case PangeaEventTypes.choreoRecord:
        return ChoreoRecordModel.fromJson(json) as V;
      case PangeaEventTypes.pangeaActivity:
        return PracticeExerciseModel.fromJson(json) as V;
      default:
        debugger(when: kDebugMode);
        throw Exception("$type events do not have pangea content");
    }
  }

  Future<PangeaAudioFile?> getPangeaAudioFile() async {
    if (type != EventTypes.Message || messageType != MessageTypes.Audio) {
      ErrorHandler.logError(
        e: "Event is not an audio message",
        data: {"event": toJson()},
      );
      return null;
    }

    final transcription = content.tryGetMap<String, dynamic>(
      MessageConstants.transcription,
    );
    final audioContent = content.tryGetMap<String, dynamic>(
      'org.matrix.msc1767.audio',
    );

    final matrixFile = await downloadAndDecryptAttachment();

    final duration =
        audioContent?.tryGet<int>(MessageConstants.duration) ??
        content
            .tryGetMap<String, dynamic>('info')
            ?.tryGet<int>(MessageConstants.duration);

    final waveform =
        audioContent?.tryGetList<int>('waveform') ??
        content
            .tryGetMap<String, dynamic>('org.matrix.msc1767.audio')
            ?.tryGetList<int>('waveform');

    // old audio messages will not have tokens
    final tokensContent = transcription?.tryGetList(ModelKey.tokens);

    final tokens = tokensContent
        ?.map((e) => TTSToken.fromJson(e as Map<String, dynamic>))
        .toList();

    return PangeaAudioFile(
      bytes: matrixFile.bytes,
      name: matrixFile.name,
      tokens: tokens,
      mimeType: matrixFile.mimeType,
      duration: duration,
      waveform: waveform,
    );
  }

  bool get isActivityMessage =>
      content[MessageConstants.messageTags] ==
      MessageConstants.messageTagActivityPlan;

  bool get isVisibleLastEvent {
    if (content.tryGet(MessageConstants.transcription) != null) {
      return false;
    }

    if ({
      EventTypes.RoomPinnedEvents,
      EventTypes.SpaceChild,
      EventTypes.SpaceParent,
      // Call membership is plumbing -- who is on the SFU right now. As a room
      // preview it read "User sent a com.famedly.call.member event", which
      // told the learner nothing and buried the last real message. The CALL
      // CARD below is the thing worth previewing.
      EventTypes.GroupCallMember,
      // The ring and the decline are plumbing too, and they arrive while the
      // learner is looking at the list. Neither has a body worth reading --
      // the CALL CARD below is what says what happened, and it lands moments
      // later.
      PangeaEventTypes.callNotification,
      PangeaEventTypes.callDecline,
    }.contains(type)) {
      return false;
    }

    if (type == EventTypes.RoomMember) {
      return roomMemberChangeType.isVisibleLastEvent;
    }

    if (type.startsWith("p.") || type.startsWith("pangea.")) {
      return {
        PangeaEventTypes.activityPlan,
        PangeaEventTypes.activitySummary,
        // A finished call belongs in the preview like any message: the card
        // carries a plain body ("Voice call (0:13)", "Missed call", "Call
        // declined") written for exactly this, so the chat list reads it
        // without knowing anything about calls.
        PangeaEventTypes.call,
      }.contains(type);
    }

    return true;
  }
}
