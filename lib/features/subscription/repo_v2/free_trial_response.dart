import 'package:fluffychat/pangea/common/utils/base_response.dart';

class FreeTrialResponse extends BaseResponse {
  FreeTrialResponse();

  @override
  Map<String, dynamic> toJson() => {};

  factory FreeTrialResponse.fromJson(Map<String, dynamic> json) =>
      FreeTrialResponse();
}
