import 'package:fluffychat/pangea/subscription/utils/subscription_duration_enum.dart';

class PaymentLinkRequest {
  final SubscriptionDuration duration;
  final bool isPromo;

  const PaymentLinkRequest({required this.duration, required this.isPromo});

  String get storageKey => "${duration.name}-$isPromo";

  Map<String, dynamic> toJson() => {
    "duration": duration.name,
    "is_promo": isPromo,
  };
}
