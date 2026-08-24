import 'package:fluffychat/features/navigation/token_params/token_param.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

class AnalyticsTokenParam extends TokenParam {
  static const String deletedLeaf = 'deleted';

  final ProgressIndicatorEnum subpage;
  final bool deleted;

  const AnalyticsTokenParam({required this.subpage, this.deleted = false});

  @override
  bool get isPushed => deleted;

  @override
  AnalyticsTokenParam? get poppedParam =>
      deleted ? AnalyticsTokenParam(subpage: subpage) : null;

  @override
  String build() => deleted ? '${subpage.route}/$deletedLeaf' : subpage.route;

  factory AnalyticsTokenParam.parse(String param) {
    final parts = param.split('/');
    return AnalyticsTokenParam(
      subpage: ProgressIndicatorEnum.fromRoute(parts.first),
      deleted: parts.length > 1 && parts[1] == deletedLeaf,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnalyticsTokenParam &&
      other.subpage.route == subpage.route &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hashAll([subpage.route, deleted]);
}
