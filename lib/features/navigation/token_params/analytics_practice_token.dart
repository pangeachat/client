import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

/// The practice panel's param: `practice:vocab` for the learner's usual
/// weak-word session, or `practice:vocab/<missionId>` for one scoped to a
/// Mission's target vocabulary (#9438). The scope rides the URL, as every
/// open panel's state does (routing.instructions.md), so a scoped session
/// survives a panel swap and a link to it opens the same scoped practice.
class AnalyticsPracticeTokenParam extends TokenParam {
  final ConstructTypeEnum constructType;
  final String? missionId;

  const AnalyticsPracticeTokenParam({
    required this.constructType,
    this.missionId,
  });

  @override
  String build() => missionId == null
      ? constructType.canonicalTokenParam
      : '${constructType.canonicalTokenParam}/$missionId';

  factory AnalyticsPracticeTokenParam.parse(String param) {
    final parts = param.split('/');
    final scope = parts.length > 1 ? parts.sublist(1).join('/') : '';
    return AnalyticsPracticeTokenParam(
      constructType: ConstructTypeEnum.fromTokenParam(parts.first),
      missionId: scope.isEmpty ? null : scope,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPracticeTokenParam &&
      other.constructType == constructType &&
      other.missionId == missionId;

  @override
  int get hashCode => Object.hashAll([constructType, missionId]);
}
