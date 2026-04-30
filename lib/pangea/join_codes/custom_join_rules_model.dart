import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/join_codes/join_code_constants.dart';

class CustomJoinRulesModel {
  final JoinRules joinRule;
  final List<Map<String, dynamic>>? allow;
  final String? accessCode;

  CustomJoinRulesModel({required this.joinRule, this.allow, this.accessCode});

  factory CustomJoinRulesModel.fromJson(Map<String, dynamic> json) {
    return CustomJoinRulesModel(
      joinRule: JoinRules.values.singleWhere(
        (element) => element.text == json[ModelKey.joinRule],
        orElse: () => JoinRules.public,
      ),
      allow: json[JoinCodeConstants.allow] != null
          ? List<Map<String, dynamic>>.from(json[JoinCodeConstants.allow])
          : null,
      accessCode: json[JoinCodeConstants.accessCode] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ModelKey.joinRule: joinRule.text,
      if (allow != null) JoinCodeConstants.allow: allow,
      if (accessCode != null) JoinCodeConstants.accessCode: accessCode,
    };
  }

  CustomJoinRulesModel copyWith({
    JoinRules? joinRule,
    List<Map<String, dynamic>>? allow,
    String? accessCode,
  }) {
    return CustomJoinRulesModel(
      joinRule: joinRule ?? this.joinRule,
      allow: allow ?? this.allow,
      accessCode: accessCode ?? this.accessCode,
    );
  }
}
