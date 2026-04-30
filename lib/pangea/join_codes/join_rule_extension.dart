import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/join_codes/custom_join_rules_model.dart';
import 'package:fluffychat/pangea/join_codes/request_room_code_extension.dart';

extension JoinRuleExtension on Client {
  Future<StateEvent> generateCustomJoinRules(
    JoinRules joinRule, {
    String? allowRoomId,
  }) async {
    String? joinCode;
    try {
      joinCode = await requestSpaceCode();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'joinRule': joinRule});
    }

    final customJoinRules = CustomJoinRulesModel(
      joinRule: joinRule,
      allow: allowRoomId != null
          ? [
              {'type': 'm.room_membership', 'room_id': allowRoomId},
            ]
          : null,
      accessCode: joinCode,
    );

    return StateEvent(
      type: EventTypes.RoomJoinRules,
      content: customJoinRules.toJson(),
    );
  }
}

extension JoinRuleExtensionOnRoom on Room {
  CustomJoinRulesModel get _customJoinRules {
    final joinRuleEvent = getState(EventTypes.RoomJoinRules);
    if (joinRuleEvent == null) {
      return CustomJoinRulesModel(joinRule: JoinRules.public);
    }
    return CustomJoinRulesModel.fromJson(joinRuleEvent.content);
  }

  String? get joinCode => _customJoinRules.accessCode;

  Future<void> setCustomJoinRules(JoinRules joinRule) async {
    final currentModel = _customJoinRules;
    if (currentModel.joinRule == joinRule) return;

    final newJoinRules = currentModel.copyWith(joinRule: joinRule);
    await _setCustomJoinRulesModel(newJoinRules);
  }

  Future<void> generateAndSetJoinCode() async {
    final currentModel = _customJoinRules;
    final newJoinRules = currentModel.copyWith(
      accessCode: await client.requestSpaceCode(),
    );
    await _setCustomJoinRulesModel(newJoinRules);
  }

  Future<void> _setCustomJoinRulesModel(CustomJoinRulesModel update) async {
    await client.setRoomStateWithKey(
      id,
      EventTypes.RoomJoinRules,
      '',
      update.toJson(),
    );
  }
}
