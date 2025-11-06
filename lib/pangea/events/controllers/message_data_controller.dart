import 'dart:async';

import 'package:async/async.dart';
import 'package:fluffychat/pangea/common/controllers/base_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/representation_content_model.dart';
import 'package:fluffychat/pangea/events/models/stt_translation_model.dart';
import 'package:fluffychat/pangea/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/events/repo/token_api_models.dart';
import 'package:fluffychat/pangea/events/repo/tokens_repo.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/translation/full_text_translation_repo.dart';
import 'package:fluffychat/pangea/translation/full_text_translation_request_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:matrix/matrix.dart' hide Result;

// TODO - make this static and take it out of the _pangeaController
// will need to pass accessToken to the requests
class MessageDataController extends BaseController {
  late PangeaController _pangeaController;

  MessageDataController(PangeaController pangeaController) {
    _pangeaController = pangeaController;
  }

  /// get tokens from the server
  /// if repEventId is not null, send the tokens to the room
  Future<Result<TokensResponseModel>> getTokens({
    required String? repEventId,
    required TokensRequestModel req,
    required Room? room,
  }) async {
    final res = await TokensRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      req,
    );
    if (res.isValue && repEventId != null && room != null) {
      room
          .sendPangeaEvent(
            content: PangeaMessageTokens(
              tokens: res.result!.tokens,
              detections: res.result!.detections,
            ).toJson(),
            parentEventId: repEventId,
            type: PangeaEventTypes.tokens,
          )
          .catchError(
            (e) => ErrorHandler.logError(
              m: "error in _getTokens.sendPangeaEvent",
              e: e,
              s: StackTrace.current,
              data: req.toJson(),
            ),
          );
    }
    return res;
  }

  /////// translation ////////

  /// get translation from the server
  /// if in cache, return from cache
  /// if not in cache, get from server
  /// send the translation to the room as a representation event
  Future<PangeaRepresentation> getPangeaRepresentation({
    required FullTextTranslationRequestModel req,
    required Event messageEvent,
  }) =>
      _getPangeaRepresentation(req: req, messageEvent: messageEvent);

  Future<PangeaRepresentation> _getPangeaRepresentation({
    required FullTextTranslationRequestModel req,
    required Event messageEvent,
  }) async {
    final res = await FullTextTranslationRepo.get(
      _pangeaController.userController.accessToken,
      req,
    );

    if (res.isError) {
      throw res.error!;
    }

    final rep = PangeaRepresentation(
      langCode: req.tgtLang,
      text: res.result!.bestTranslation,
      originalSent: false,
      originalWritten: false,
    );

    messageEvent.room
        .sendPangeaEvent(
          content: rep.toJson(),
          parentEventId: messageEvent.eventId,
          type: PangeaEventTypes.representation,
        )
        .catchError(
          (e) => ErrorHandler.logError(
            m: "error in _getPangeaRepresentation.sendPangeaEvent",
            e: e,
            s: StackTrace.current,
            data: req.toJson(),
          ),
        );

    return rep;
  }

  Future<String?> getPangeaRepresentationEvent({
    required FullTextTranslationRequestModel req,
    required PangeaMessageEvent messageEvent,
    bool originalSent = false,
  }) async {
    final res = await FullTextTranslationRepo.get(
      _pangeaController.userController.accessToken,
      req,
    );

    if (res.isError) {
      return null;
    }

    if (originalSent && messageEvent.originalSent != null) {
      originalSent = false;
    }

    final rep = PangeaRepresentation(
      langCode: req.tgtLang,
      text: res.result!.bestTranslation,
      originalSent: originalSent,
      originalWritten: false,
    );

    try {
      final repEvent = await messageEvent.room.sendPangeaEvent(
        content: rep.toJson(),
        parentEventId: messageEvent.eventId,
        type: PangeaEventTypes.representation,
      );
      return repEvent?.eventId;
    } catch (e, s) {
      ErrorHandler.logError(
        m: "error in _getPangeaRepresentation.sendPangeaEvent",
        e: e,
        s: s,
        data: req.toJson(),
      );
      return null;
    }
  }

  Future<SttTranslationModel> getSttTranslation({
    required String? repEventId,
    required FullTextTranslationRequestModel req,
    required Room? room,
  }) =>
      _getSttTranslation(
        repEventId: repEventId,
        req: req,
        room: room,
      );

  Future<SttTranslationModel> _getSttTranslation({
    required String? repEventId,
    required FullTextTranslationRequestModel req,
    required Room? room,
  }) async {
    final res = await FullTextTranslationRepo.get(
      _pangeaController.userController.accessToken,
      req,
    );

    if (res.isError) {
      throw res.error!;
    }

    final translation = SttTranslationModel(
      translation: res.result!.bestTranslation,
      langCode: req.tgtLang,
    );

    if (repEventId != null && room != null) {
      room
          .sendPangeaEvent(
            content: translation.toJson(),
            parentEventId: repEventId,
            type: PangeaEventTypes.sttTranslation,
          )
          .catchError(
            (e) => ErrorHandler.logError(
              m: "error in _getSttTranslation.sendPangeaEvent",
              e: e,
              s: StackTrace.current,
              data: req.toJson(),
            ),
          );
    }

    return translation;
  }
}
