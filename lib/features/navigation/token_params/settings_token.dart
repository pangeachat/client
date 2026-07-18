import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class SettingsTokenParam extends TokenParam {
  final String subpage;
  final String? planId;
  const SettingsTokenParam({required this.subpage, this.planId});

  @override
  bool get isPushed => subpage.contains('/');

  @override
  SettingsTokenParam? get poppedParam => isPushed
      ? SettingsTokenParam(
          subpage: subpage.substring(0, subpage.lastIndexOf('/')),
        )
      : null;

  @override
  String build() {
    if (subpage == 'subscription/selected') {
      final planId = this.planId;
      return TokenFields.join([
        subpage,
        if (planId != null) TokenFields.encode(planId),
      ]);
    }
    return subpage;
  }

  factory SettingsTokenParam.parse(String param) {
    if (param.startsWith('subscription/selected')) {
      final chunks = TokenFields.split(param);
      if (chunks.length < 2) {
        return SettingsTokenParam(subpage: 'subscription/selected');
      }
      final planId = TokenFields.decode(chunks[1]);
      return SettingsTokenParam(
        subpage: 'subscription/selected',
        planId: planId,
      );
    }
    return SettingsTokenParam(subpage: param);
  }

  @override
  bool operator ==(Object other) =>
      other is SettingsTokenParam && other.subpage == subpage;

  @override
  int get hashCode => Object.hashAll([subpage]);
}
