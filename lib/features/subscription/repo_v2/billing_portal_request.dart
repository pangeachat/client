import 'package:fluffychat/pangea/common/utils/base_request.dart';

class BillingPortalRequest extends BaseRequest {
  @override
  String get storageKey => "billing_portal";

  @override
  Map<String, dynamic> toJson() => {};
}
