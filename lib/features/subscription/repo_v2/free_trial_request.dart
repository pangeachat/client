import 'package:fluffychat/pangea/common/utils/base_request.dart';

class FreeTrialRequest extends BaseRequest {
  @override
  String get storageKey => "activate_free_trial";

  @override
  Map<String, dynamic> toJson() => {};
}
