import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/choreographer/repo/full_text_translation_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/tokens_repo.dart';
import 'package:fluffychat/pangea/common/controllers/base_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/representation_content_model.dart';
import 'package:fluffychat/pangea/events/models/stt_translation_model.dart';
import 'package:fluffychat/pangea/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/events/repo/token_api_models.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';

// TODO - make this static and take it out of the _pangeaController
// will need to pass accessToken to the requests
class MessageDataController extends BaseController {
  late PangeaController _pangeaController;

  final Map<int, Future<TokensResponseModel>> _tokensCache = {};
  final Map<int, Future<PangeaRepresentation>> _representationCache = {};
  final Map<int, Future<SttTranslationModel>> _sttTranslationCache = {};
  late Timer _cacheTimer;

  MessageDataController(PangeaController pangeaController) {
    _pangeaController = pangeaController;
    _startCacheTimer();
  }

  /// Starts a timer that clears the cache every 10 minutes
  void _startCacheTimer() {
    _cacheTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _clearCache();
    });
  }

  /// Clears the token and representation caches
  void _clearCache() {
    _tokensCache.clear();
    _representationCache.clear();
    _sttTranslationCache.clear();
    debugPrint("message data cache cleared.");
  }

  @override
  void dispose() {
    _cacheTimer.cancel(); // Cancel the timer when the controller is disposed
    super.dispose();
  }

  /// get tokens from the server
  /// if repEventId is not null, send the tokens to the room
  Future<TokensResponseModel> _getTokens({
    required String? repEventId,
    required TokensRequestModel req,
    required Room? room,
  }) async {
    final TokensResponseModel res = await TokensRepo.get(
      _pangeaController.userController.accessToken,
      request: req,
    );
    if (repEventId != null && room != null) {
      room
          .sendPangeaEvent(
            content: PangeaMessageTokens(
              tokens: res.tokens,
              detections: res.detections,
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

  /// get tokens from the server
  /// first check if the tokens are in the cache
  /// if repEventId is not null, send the tokens to the room
  Future<TokensResponseModel> getTokens({
    required String? repEventId,
    required TokensRequestModel req,
    required Room? room,
  }) =>
      _tokensCache[req.hashCode] ??= _getTokens(
        repEventId: repEventId,
        req: req,
        room: room,
      ).catchError((e, s) {
        _tokensCache.remove(req.hashCode);
        return Future<TokensResponseModel>.error(e, s);
      });

  /////// translation ////////

  /// get translation from the server
  /// if in cache, return from cache
  /// if not in cache, get from server
  /// send the translation to the room as a representation event
  Future<PangeaRepresentation> getPangeaRepresentation({
    required FullTextTranslationRequestModel req,
    required Event messageEvent,
  }) async {
    return _representationCache[req.hashCode] ??=
        _getPangeaRepresentation(req: req, messageEvent: messageEvent);
  }

  Future<PangeaRepresentation> _getPangeaRepresentation({
    required FullTextTranslationRequestModel req,
    required Event messageEvent,
  }) async {
    final FullTextTranslationResponseModel res =
        await FullTextTranslationRepo.translate(
      accessToken: _pangeaController.userController.accessToken,
      request: req,
    );

    final rep = PangeaRepresentation(
      langCode: req.tgtLang,
      text: res.bestTranslation,
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
    final FullTextTranslationResponseModel res =
        await FullTextTranslationRepo.translate(
      accessToken: _pangeaController.userController.accessToken,
      request: req,
    );

    if (originalSent && messageEvent.originalSent != null) {
      originalSent = false;
    }

    final rep = PangeaRepresentation(
      langCode: req.tgtLang,
      text: res.bestTranslation,
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

  Future<void> sendTokensEvent({
    required String repEventId,
    required TokensRequestModel req,
    required Room room,
  }) async {
    final TokensResponseModel res = await TokensRepo.get(
      _pangeaController.userController.accessToken,
      request: req,
    );

    try {
      await room.sendPangeaEvent(
        content: PangeaMessageTokens(
          tokens: res.tokens,
          detections: res.detections,
        ).toJson(),
        parentEventId: repEventId,
        type: PangeaEventTypes.tokens,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        m: "error in _getTokens.sendPangeaEvent",
        e: e,
        s: s,
        data: req.toJson(),
      );
    }
  }

  Future<SttTranslationModel> getSttTranslation({
    required String? repEventId,
    required FullTextTranslationRequestModel req,
    required Room? room,
  }) =>
      _sttTranslationCache[req.hashCode] ??= _getSttTranslation(
        repEventId: repEventId,
        req: req,
        room: room,
      ).catchError((e, s) {
        _sttTranslationCache.remove(req.hashCode);
        return Future<SttTranslationModel>.error(e, s);
      });

  Future<SttTranslationModel> _getSttTranslation({
    required String? repEventId,
    required FullTextTranslationRequestModel req,
    required Room? room,
  }) async {
    final res = await FullTextTranslationRepo.translate(
      accessToken: _pangeaController.userController.accessToken,
      request: req,
    );

    final translation = SttTranslationModel(
      translation: res.bestTranslation,
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
