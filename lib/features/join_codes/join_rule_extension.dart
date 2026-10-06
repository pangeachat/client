import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/custom_join_rules_model.dart';
import 'package:fluffychat/features/join_codes/request_room_code_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

extension JoinRuleExtension on Client {
  /// A fresh join code, or null if the request fails. A failure is logged and
  /// the room is created without a code, so this never throws.
  Future<String?> requestJoinCodeOrNull() async {
    try {
      return await requestSpaceCode();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return null;
    }
  }

  /// [joinCode] lets a caller start the code request early, alongside other
  /// work; without it, the code is requested here.
  Future<StateEvent> generateCustomJoinRules(
    JoinRules joinRule, {
    String? allowRoomId,
    List<String>? allowRoomIds,
    Future<String?>? joinCode,
  }) async {
    final accessCode = await (joinCode ?? requestJoinCodeOrNull());

    final allRoomIds = {?allowRoomId, ...?allowRoomIds};
    final customJoinRules = CustomJoinRulesModel(
      joinRule: joinRule,
      allow: allRoomIds.isNotEmpty
          ? allRoomIds
                .map((id) => {'type': 'm.room_membership', 'room_id': id})
                .toList()
          : null,
      accessCode: accessCode,
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
