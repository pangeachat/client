import 'package:fluffychat/features/subscription/utils/subscription_duration_enum.dart';

class ValidatePromoCodeRequest {
  final String code;
  final SubscriptionDuration? duration;

  const ValidatePromoCodeRequest({required this.code, this.duration});

  String get storageKey => "$code-${duration?.name}";

  Map<String, dynamic> toJson() => {"code": code, "duration": duration?.name};
}
