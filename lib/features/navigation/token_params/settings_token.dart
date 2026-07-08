import 'package:fluffychat/features/navigation/token_params/token_param.dart';

class SettingsTokenParam extends TokenParam {
  final String subpage;
  const SettingsTokenParam({required this.subpage});

  @override
  bool get isPushed => subpage.contains('/');

  @override
  TokenParam? get poppedParam => isPushed
      ? SettingsTokenParam(
          subpage: subpage.substring(0, subpage.lastIndexOf('/')),
        )
      : null;

  @override
  String build() => subpage;

  factory SettingsTokenParam.parse(String param) =>
      SettingsTokenParam(subpage: param);

  @override
  bool operator ==(Object other) =>
      other is SettingsTokenParam && other.subpage == subpage;

  @override
  int get hashCode => Object.hashAll([subpage]);
}
