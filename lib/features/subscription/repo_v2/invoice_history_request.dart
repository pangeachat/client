import 'package:fluffychat/pangea/common/utils/base_request.dart';

class InvoiceHistoryRequest extends BaseRequest {
  final String userID;
  InvoiceHistoryRequest({required this.userID});

  @override
  String get storageKey => "invoice_history_$userID";

  @override
  Map<String, dynamic> toJson() => {};
}
