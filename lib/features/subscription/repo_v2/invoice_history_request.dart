import 'package:fluffychat/pangea/common/utils/base_request.dart';

class InvoiceHistoryRequest extends BaseRequest {
  @override
  String get storageKey => "subscription_history";

  @override
  Map<String, dynamic> toJson() => {};
}
