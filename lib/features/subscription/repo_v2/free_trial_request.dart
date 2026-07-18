import 'package:fluffychat/pangea/common/utils/base_request.dart';

class FreeTrialRequest extends BaseRequest {
  final String userID;
  FreeTrialRequest({required this.userID});

  @override
  String get storageKey => "activate_free_trial_$userID";

  @override
  Map<String, dynamic> toJson() => {};
}
