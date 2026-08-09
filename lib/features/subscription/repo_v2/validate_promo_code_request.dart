import 'package:fluffychat/features/subscription/enums/subscription_duration_enum.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';

class ValidatePromoCodeRequest extends BaseRequest {
  final String userID;
  final String code;
  final SubscriptionDuration? duration;

  ValidatePromoCodeRequest({
    required this.userID,
    required this.code,
    this.duration,
  });

  @override
  String get storageKey =>
      "validate_promo_code_${userID}_${code}_${duration?.name}";

  @override
  Map<String, dynamic> toJson() => {"code": code, "duration": duration?.name};
}
