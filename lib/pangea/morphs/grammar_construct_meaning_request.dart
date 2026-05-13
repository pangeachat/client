import 'package:fluffychat/pangea/common/utils/base_request.dart';

class GrammarConstructMeaningRequest extends BaseRequest {
  final String targetLanguage;
  final String userL1;
  final String feature;

  GrammarConstructMeaningRequest({
    required this.targetLanguage,
    required this.userL1,
    required this.feature,
  });

  @override
  String get storageKey => "construct-meaning-$targetLanguage-$userL1-$feature";

  @override
  Map<String, dynamic> toJson() => {
    "target_language": targetLanguage,
    "user_l1": userL1,
    "feature": feature,
  };
}
