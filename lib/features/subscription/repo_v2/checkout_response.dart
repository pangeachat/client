import 'package:fluffychat/features/subscription/enums/checkout_status_enum.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';

class CheckoutResponse extends BaseResponse {
  final CheckoutStatus status;
  final String? sessionUrl;
  final int? retryAfterSeconds;
  final String? appliedPromoCode;

  const CheckoutResponse({
    required this.status,
    this.sessionUrl,
    this.retryAfterSeconds,
    this.appliedPromoCode,
  });

  factory CheckoutResponse.fromJson(Map<String, dynamic> json) {
    return CheckoutResponse(
      status: CheckoutStatus.fromJson(json['status'] as String),
      sessionUrl: json['sessionUrl'] as String?,
      retryAfterSeconds: json['retryAfterSeconds'] as int?,
      appliedPromoCode: json['appliedPromoCode'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'status': status.toJson(),
      'sessionUrl': sessionUrl,
      'retryAfterSeconds': retryAfterSeconds,
      'appliedPromoCode': appliedPromoCode,
    };
  }

  bool get isReady =>
      status == CheckoutStatus.created || status == CheckoutStatus.reused;

  bool get isCreating => status == CheckoutStatus.creating;
}
