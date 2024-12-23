import 'dart:developer';

import 'package:fluffychat/pangea/constants/model_keys.dart';
import 'package:fluffychat/pangea/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/controllers/text_to_speech_controller.dart';
import 'package:fluffychat/pangea/models/choreo_record.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/practice_activity_model.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/practice_activity_record_model.dart';
import 'package:fluffychat/pangea/models/representation_content_model.dart';
import 'package:fluffychat/pangea/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/widgets/chat/message_audio_card.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

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
        return ChoreoRecord.fromJson(json) as V;
      case PangeaEventTypes.pangeaActivity:
        return PracticeActivityModel.fromJson(json) as V;
      case PangeaEventTypes.activityRecord:
        return PracticeActivityRecordModel.fromJson(json) as V;
      default:
        debugger(when: kDebugMode);
        throw Exception("$type events do not have pangea content");
    }
  }

  Future<PangeaAudioFile?> getPangeaAudioFile() async {
    if (type != EventTypes.Message || messageType != MessageTypes.Audio) {
      ErrorHandler.logError(
        e: "Event is not an audio message",
        data: {
          "event": toJson(),
        },
      );
      return null;
    }

    final transcription =
        content.tryGetMap<String, dynamic>(ModelKey.transcription);
    final audioContent =
        content.tryGetMap<String, dynamic>('org.matrix.msc1767.audio');
    if (transcription == null || audioContent == null) {
      ErrorHandler.logError(
        e: "Called getPangeaAudioFile on an audio message without transcription or audio content",
        data: {},
      );
      return null;
    }

    final matrixFile = await downloadAndDecryptAttachment();
    final duration = audioContent.tryGet<int>('duration');
    final waveform = audioContent.tryGetList<int>('waveform');

    // old audio messages will not have tokens
    final tokensContent = transcription.tryGetList(ModelKey.tokens);
    if (tokensContent == null) return null;

    final tokens = tokensContent
        .map((e) => TTSToken.fromJson(e as Map<String, dynamic>))
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
}
