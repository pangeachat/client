import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/join_codes/space_code_extension.dart';

extension JoinRuleExtension on Client {
  Future<StateEvent> pangeaJoinRules(
    String joinRule, {
    List<Map<String, dynamic>>? allow,
  }) async {
    String? joinCode;
    try {
      joinCode = await requestSpaceCode();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'joinRule': joinRule});
    }

    final Map<String, dynamic> content = {ModelKey.joinRule: joinRule};

    if (joinCode != null) {
      content[ModelKey.accessCode] = joinCode;
    }

    if (allow != null) {
      content['allow'] = allow;
    }

    return StateEvent(type: EventTypes.RoomJoinRules, content: content);
  }
}

extension JoinRuleExtensionOnRoom on Room {
  Future<void> addJoinCode() async {
    if (!canChangeStateEvent(EventTypes.RoomJoinRules)) {
      throw Exception('Cannot change join rules for this room');
    }

    final currentJoinRules = getState(EventTypes.RoomJoinRules)?.content ?? {};
    if (currentJoinRules[ModelKey.accessCode] != null) return;

    final joinCode = await client.requestSpaceCode();
    currentJoinRules[ModelKey.accessCode] = joinCode;

    await client.setRoomStateWithKey(
      id,
      EventTypes.RoomJoinRules,
      '',
      currentJoinRules,
    );
  }

  /// Keep the room's current join rule state event content (except for what's intentionally replaced)
  /// since space's access codes were stored there. Don't want to accidentally remove them.
  Future<void> pangeaSetJoinRules(
    String joinRule, {
    List<Map<String, dynamic>>? allow,
  }) async {
    final currentJoinRule = getState(EventTypes.RoomJoinRules)?.content ?? {};

    if (currentJoinRule[ModelKey.joinRule] == joinRule &&
        (currentJoinRule['allow'] == allow)) {
      return; // No change needed
    }

    currentJoinRule[ModelKey.joinRule] = joinRule;
    currentJoinRule['allow'] = allow;

    await client.setRoomStateWithKey(
      id,
      EventTypes.RoomJoinRules,
      '',
      currentJoinRule,
    );
  }
}
