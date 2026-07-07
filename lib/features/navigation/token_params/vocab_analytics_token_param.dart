import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class VocabAnalyticsTokenParam extends TokenParam {
  final ConstructIdentifier? constructId;
  const VocabAnalyticsTokenParam({required this.constructId}) : super('vocab');

  @override
  String build() => constructId?.toTokenParam() ?? '';

  factory VocabAnalyticsTokenParam.parse(String param) =>
      VocabAnalyticsTokenParam(
        constructId: ConstructIdentifier.fromTokenParam(
          ConstructTypeEnum.vocab,
          param,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is VocabAnalyticsTokenParam &&
      other.type == type &&
      other.constructId?.toTokenParam() == constructId?.toTokenParam();

  @override
  int get hashCode => Object.hash(type, constructId?.toTokenParam());
}
