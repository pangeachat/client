import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/extensions/pangea_event_extension.dart';
import '../../choreographer/choreo_record_model.dart';
import '../constants/pangea_event_types.dart';

class ChoreoEvent {
  Event event;
  ChoreoRecordModel? _content;

  ChoreoEvent({required this.event}) {
    if (event.type != PangeaEventTypes.choreoRecord) {
      throw Exception(
        "${event.type} should not be used to make a ChoreoEvent",
      );
    }
  }

  ChoreoRecordModel? get content {
    try {
      _content ??= event.getPangeaContent<ChoreoRecordModel>();
      return _content;
    } catch (err, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: err,
        s: s,
        data: {
          "event": event.toJson(),
        },
      );
      return null;
    }
  }
}
