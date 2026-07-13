import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class AnalyticsPracticeTokenParam extends TokenParam {
  final ConstructTypeEnum constructType;
  const AnalyticsPracticeTokenParam({required this.constructType});

  @override
  String build() => constructType.canonicalTokenParam;

  factory AnalyticsPracticeTokenParam.parse(String param) =>
      AnalyticsPracticeTokenParam(
        constructType: ConstructTypeEnum.fromTokenParam(param),
      );

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPracticeTokenParam &&
      other.constructType == constructType;

  @override
  int get hashCode => Object.hashAll([constructType]);
}
