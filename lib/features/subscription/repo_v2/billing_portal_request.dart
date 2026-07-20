import 'package:fluffychat/pangea/common/utils/base_request.dart';

class BillingPortalRequest extends BaseRequest {
  final String userID;
  BillingPortalRequest({required this.userID});

  @override
  String get storageKey => "billing_portal_$userID";

  @override
  Map<String, dynamic> toJson() => {};
}
