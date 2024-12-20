import 'dart:developer';

import 'package:fluffychat/pangea/extensions/pangea_event_extension.dart';
import 'package:fluffychat/pangea/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../constants/pangea_event_types.dart';

class TokensEvent {
  Event event;
  PangeaMessageTokens? _content;

  TokensEvent({required this.event}) {
    if (event.type != PangeaEventTypes.tokens) {
      throw Exception(
        "${event.type} should not be used to make a TokensEvent",
      );
    }
  }

  PangeaMessageTokens? get _pangeaMessageTokens {
    try {
      _content ??= event.getPangeaContent<PangeaMessageTokens>();
      return _content!;
    } catch (err, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: err, s: s);
      return null;
    }
  }

  PangeaMessageTokens? get tokens => _pangeaMessageTokens;
}
