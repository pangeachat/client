import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/chat_settings/constants/bot_mode.dart';
import 'package:fluffychat/pangea/chat_settings/models/bot_options_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension BotRoomExtension on Room {
  bool get isBotDM {
    if (isDirectChat && directChatMatrixID == BotName.byEnvironment) {
      return true;
    }
    if (botOptions?.mode == BotMode.directChat) {
      return true;
    }
    return false;
  }

  BotOptionsModel? get botOptions {
    if (isSpace) return null;
    final stateEvent = getState(PangeaEventTypes.botOptions);
    if (stateEvent == null) return null;
    return BotOptionsModel.fromJson(stateEvent.content);
  }

  Future<void> setBotOptions(BotOptionsModel options) async {
    if (!canChangeStateEvent(PangeaEventTypes.botOptions)) {
      Logs().w("User doesn't have permission to set bot options in room $id");
      return;
    }

    const maxRetries = 3;
    Duration retryDelay = const Duration(seconds: 5);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          await Future.delayed(retryDelay);
          retryDelay *= 2;
        }

        await client.setRoomStateWithKey(
          id,
          PangeaEventTypes.botOptions,
          '',
          options.toJson(),
        );

        return;
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'roomId': id, 'options': options.toJson(), 'attempt': attempt},
        );

        if (attempt == maxRetries) {
          rethrow;
        }
      }
    }
  }

  Future<void> sendRegenerationRequest(String eventId, {String? reason}) =>
      sendEvent({
        "m.relates_to": {
          "rel_type": PangeaEventTypes.regenerationRequest,
          "event_id": eventId,
        },
        PangeaEventTypes.regenerationRequest: {"reason": reason},
      }, type: PangeaEventTypes.regenerationRequest);

  Future<void> sendNotificationOpenedEvent(
    String eventId, {
    String? checkInType,
  }) => sendEvent({
    'notification_event_id': eventId,
    'check_in_type': checkInType,
    'opened_at_ts': DateTime.now().millisecondsSinceEpoch,
  }, type: PangeaEventTypes.botNotificationOpened);
}
