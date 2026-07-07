import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class GrammarAnalyticsTokenParam extends TokenParam {
  final ConstructIdentifier? constructId;
  const GrammarAnalyticsTokenParam({required this.constructId})
    : super('grammar');

  @override
  String build() => constructId?.toTokenParam() ?? '';

  factory GrammarAnalyticsTokenParam.parse(String param) =>
      GrammarAnalyticsTokenParam(
        constructId: ConstructIdentifier.fromTokenParam(
          ConstructTypeEnum.morph,
          param,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is GrammarAnalyticsTokenParam &&
      other.type == type &&
      other.constructId?.toTokenParam() == constructId?.toTokenParam();

  @override
  int get hashCode => Object.hash(type, constructId?.toTokenParam());
}
