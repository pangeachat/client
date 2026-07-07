import 'package:fluffychat/features/navigation/token_params/token_param.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

class AnalyticsTokenParam extends TokenParam {
  final ProgressIndicatorEnum subpage;
  const AnalyticsTokenParam({required this.subpage}) : super('analytics');

  @override
  String build() => subpage.route;

  factory AnalyticsTokenParam.parse(String param) =>
      AnalyticsTokenParam(subpage: ProgressIndicatorEnum.fromRoute(param));

  @override
  bool operator ==(Object other) =>
      other is AnalyticsTokenParam &&
      other.type == type &&
      other.subpage.route == subpage.route;

  @override
  int get hashCode => Object.hash(type, subpage.route);
}
