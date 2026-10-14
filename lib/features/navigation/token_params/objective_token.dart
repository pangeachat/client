import 'package:fluffychat/features/navigation/token_params/token_param.dart';

/// The Learning Objective (Mission) whose detail panel is open:
/// `objective:<missionId>`, the Learning Objectives list's analogue of a
/// `vocab:` construct detail.
class ObjectiveTokenParam extends TokenParam {
  final String missionId;
  const ObjectiveTokenParam({required this.missionId});

  @override
  String build() => missionId;

  factory ObjectiveTokenParam.parse(String param) =>
      ObjectiveTokenParam(missionId: param);

  @override
  bool operator ==(Object other) =>
      other is ObjectiveTokenParam && other.missionId == missionId;

  @override
  int get hashCode => missionId.hashCode;
}
