import 'package:fluffychat/pangea/common/utils/base_response.dart';

class BillingPortalResponse extends BaseResponse {
  final String url;
  BillingPortalResponse({required this.url});

  @override
  Map<String, dynamic> toJson() => {"url": url};

  factory BillingPortalResponse.fromJson(Map<String, dynamic> json) =>
      BillingPortalResponse(url: json["url"] as String);
}
