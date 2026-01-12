// ignore_for_file: implementation_imports

import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/choreographer/choreo_record_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_choreo_event.dart';
import 'package:fluffychat/pangea/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/pangea/events/models/language_detection_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/representation_content_model.dart';
import 'package:fluffychat/pangea/events/models/stt_translation_model.dart';
import 'package:fluffychat/pangea/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/events/repo/token_api_models.dart';
import 'package:fluffychat/pangea/events/repo/tokens_repo.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class RepresentationEvent {
  Event? _event;
  PangeaRepresentation? _content;
  PangeaMessageTokens? _tokens;
  ChoreoRecordModel? _choreo;
  Timeline timeline;
  Event parentMessageEvent;

  RepresentationEvent({
    required this.timeline,
    required this.parentMessageEvent,
    Event? event,
    PangeaRepresentation? content,
    PangeaMessageTokens? tokens,
    ChoreoRecordModel? choreo,
  }) {
    if (event != null && event.type != PangeaEventTypes.representation) {
      throw Exception(
        "${event.type} should not be used to make a RepresentationEvent",
      );
    }
    _event = event;
    _content = content;
    _tokens = tokens;
    _choreo = choreo;
  }

  Event? get event => _event;

  String get text => content.text;

  String get langCode => content.langCode;

  List<LanguageDetectionModel>? get detections => _tokens?.detections;

  Set<Event> get tokenEvents =>
      _event?.aggregatedEvents(
        timeline,
        PangeaEventTypes.tokens,
      ) ??
      {};

  Set<Event> get sttEvents =>
      _event?.aggregatedEvents(
        timeline,
        PangeaEventTypes.sttTranslation,
      ) ??
      {};

  Set<Event> get choreoEvents =>
      _event?.aggregatedEvents(
        timeline,
        PangeaEventTypes.choreoRecord,
      ) ??
      {};

  // Note: in the case where the event is the originalSent or originalWritten event,
  // the content will be set on initialization by the PangeaMessageEvent
  // Otherwise, the content will be fetched from the event where it is stored in content[type]
  PangeaRepresentation get content {
    if (_content != null) return _content!;
    _content = _event?.getPangeaContent<PangeaRepresentation>();
    return _content!;
  }

  List<PangeaToken>? get tokens {
    if (_tokens != null) return _tokens!.tokens;
    if (_event == null) return null;

    if (tokenEvents.isEmpty) return null;
    _tokens = tokenEvents.last.getPangeaContent<PangeaMessageTokens>();
    return _tokens?.tokens;
  }

  ChoreoRecordModel? get choreo {
    if (_choreo != null) return _choreo;

    if (_event == null) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: "_event and _choreo both null",
        ),
      );
      return null;
    }

    if (choreoEvents.isEmpty) return null;
    if (choreoEvents.length > 1) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        m: 'should not have more than one choreoEvent per representation ${_event?.eventId}',
        s: StackTrace.current,
        data: {"event": _event?.toJson()},
      );
    }

    return ChoreoEvent(event: choreoEvents.first).content;
  }

  List<SttTranslationModel> get sttTranslations {
    if (content.speechToText == null) return [];
    if (_event == null) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: "_event and _sttTranslations both null",
        ),
      );
      return [];
    }

    if (sttEvents.isEmpty) return [];
    final List<SttTranslationModel> sttTranslations = [];
    for (final event in sttEvents) {
      try {
        sttTranslations.add(
          SttTranslationModel.fromJson(event.content),
        );
      } catch (e) {
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: "Failed to parse STT translation",
            data: {
              "eventID": event.eventId,
              "content": event.content,
              "error": e.toString(),
            },
          ),
        );
      }
    }
    return sttTranslations;
  }

  List<OneConstructUse> get vocabAndMorphUses {
    if (tokens == null || tokens!.isEmpty) {
      return [];
    }

    final metadata = ConstructUseMetaData(
      roomId: parentMessageEvent.room.id,
      timeStamp: parentMessageEvent.originServerTs,
      eventId: parentMessageEvent.eventId,
    );

    return content.vocabAndMorphUses(
      tokens: tokens!,
      metadata: metadata,
      choreo: choreo,
    );
  }

  /// Finds the closest non-punctuation token to the given token.
  PangeaToken? getClosestNonPunctToken(PangeaToken token) {
    // If it's not punctuation, it's already the closest.
    if (token.pos != "PUNCT") return token;

    final list = tokens;
    if (list == null) return null;

    final index = list.indexOf(token);
    if (index == -1) return null;

    PangeaToken? left;
    PangeaToken? right;

    // Scan left
    for (int i = index - 1; i >= 0; i--) {
      if (list[i].pos != "PUNCT") {
        left = list[i];
        break;
      }
    }

    // Scan right
    for (int i = index + 1; i < list.length; i++) {
      if (list[i].pos != "PUNCT") {
        right = list[i];
        break;
      }
    }

    if (left == null) return right;
    if (right == null) return left;

    // Choose the nearest by distance
    final leftDistance = token.start - left.end;
    final rightDistance = right.start - token.end;

    return leftDistance < rightDistance ? left : right;
  }

  Future<Result<List<PangeaToken>>> requestTokens() async {
    if (tokens != null) return Result.value(tokens!);
    final res = await TokensRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      TokensRequestModel(
        fullText: text,
        langCode: langCode,
        senderL1:
            MatrixState.pangeaController.userController.userL1?.langCode ??
                LanguageKeys.unknownLanguage,
        senderL2:
            MatrixState.pangeaController.userController.userL2?.langCode ??
                LanguageKeys.unknownLanguage,
      ),
    );

    if (_event != null) {
      _event!.room.sendPangeaEvent(
        content: PangeaMessageTokens(
          tokens: res.result!.tokens,
          detections: res.result!.detections,
        ).toJson(),
        parentEventId: _event!.eventId,
        type: PangeaEventTypes.tokens,
      );
    }

    return res.isError
        ? Result.error(res.error!)
        : Result.value(res.result!.tokens);
  }

  SttTranslationModel? getSpeechToTextTranslationLocal(String langCode) {
    return sttTranslations.firstWhereOrNull((t) => t.langCode == langCode);
  }
}
