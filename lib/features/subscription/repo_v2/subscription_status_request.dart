import 'package:fluffychat/pangea/common/utils/base_request.dart';

class SubscriptionStatusRequest extends BaseRequest {
  @override
  String get storageKey => "subscription_status";

  @override
  Map<String, dynamic> toJson() => {};
}
