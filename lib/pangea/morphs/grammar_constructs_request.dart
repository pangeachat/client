import 'package:fluffychat/pangea/common/utils/base_request.dart';

class GrammarConstructsRequest extends BaseRequest {
  final String targetLanguage;
  final String userL1;

  GrammarConstructsRequest({
    required this.targetLanguage,
    required this.userL1,
  });

  @override
  String get storageKey => "constructs-$targetLanguage-$userL1";

  @override
  Map<String, dynamic> toJson() => {
    "target_language": targetLanguage,
    "user_l1": userL1,
  };
}
