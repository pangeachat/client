import 'package:fluffychat/pangea/common/utils/base_request.dart';

class SubscriptionStatusRequest extends BaseRequest {
  final String userID;
  SubscriptionStatusRequest({required this.userID});

  @override
  String get storageKey => "subscription_status_$userID";

  @override
  Map<String, dynamic> toJson() => {};
}
