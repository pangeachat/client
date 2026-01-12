import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';

extension UserLemmaInfoExtension on Room {
  UserSetLemmaInfo getUserSetLemmaInfo(ConstructIdentifier cId) {
    final state = getState(PangeaEventTypes.userSetLemmaInfo, cId.string);
    if (state == null) return UserSetLemmaInfo();
    try {
      return UserSetLemmaInfo.fromJson(state.content);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "roomID": id,
          "stateContent": state.content,
          "stateKey": state.stateKey,
        },
      );
      return UserSetLemmaInfo();
    }
  }

  String? constructEmoji(ConstructIdentifier cId) {
    final info = getUserSetLemmaInfo(cId);
    return info.emojis?.firstOrNull;
  }

  Future<void> setUserSetLemmaInfo(
    ConstructIdentifier cId,
    UserSetLemmaInfo info,
  ) async {
    final syncFuture = client.onRoomState.stream.firstWhere((event) {
      return event.roomId == id &&
          event.state.type == PangeaEventTypes.userSetLemmaInfo;
    });
    client.setRoomStateWithKey(
      id,
      PangeaEventTypes.userSetLemmaInfo,
      cId.string,
      info.toJson(),
    );
    await syncFuture.timeout(const Duration(seconds: 10));
  }
}
