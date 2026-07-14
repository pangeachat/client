import 'package:fluffychat/pangea/common/utils/base_response.dart';

class ValidatePromoCodeResponse extends BaseResponse {
  final bool? valid;
  final String? code;
  final String? discountType;
  final double? percentOff;
  final int? amountOff;
  final String? currency;
  final String? couponDuration;
  final PromoRestrictions? restrictions;
  final DiscountedPrice? discountedPrice;
  final DateTime? expiresAt;
  final String? reason;

  const ValidatePromoCodeResponse({
    this.valid,
    this.code,
    this.discountType,
    this.percentOff,
    this.amountOff,
    this.currency,
    this.couponDuration,
    this.restrictions,
    this.discountedPrice,
    this.expiresAt,
    this.reason,
  });

  factory ValidatePromoCodeResponse.fromJson(Map<String, dynamic> json) {
    return ValidatePromoCodeResponse(
      valid: json['valid'] as bool?,
      code: json['code'] as String?,
      discountType: json['discount_type'] as String?,
      percentOff: (json['percent_off'] as num?)?.toDouble(),
      amountOff: json['amount_off'] as int?,
      currency: json['currency'] as String?,
      couponDuration: json['coupon_duration'] as String?,
      restrictions: json['restrictions'] != null
          ? PromoRestrictions.fromJson(
              json['restrictions'] as Map<String, dynamic>,
            )
          : null,
      discountedPrice: json['discounted_price'] != null
          ? DiscountedPrice.fromJson(
              json['discounted_price'] as Map<String, dynamic>,
            )
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['expires_at'] as int) * 1000,
            )
          : null,
      reason: json['reason'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'valid': valid,
      'code': code,
      'discount_type': discountType,
      'percent_off': percentOff,
      'amount_off': amountOff,
      'currency': currency,
      'coupon_duration': couponDuration,
      'restrictions': restrictions?.toJson(),
      'discounted_price': discountedPrice?.toJson(),
      'expires_at': expiresAt?.millisecondsSinceEpoch,
      'reason': reason,
    };
  }
}

class PromoRestrictions {
  final bool? firstTimeTransaction;
  final int? minimumAmount;
  final String? minimumAmountCurrency;

  const PromoRestrictions({
    this.firstTimeTransaction,
    this.minimumAmount,
    this.minimumAmountCurrency,
  });

  factory PromoRestrictions.fromJson(Map<String, dynamic> json) {
    return PromoRestrictions(
      firstTimeTransaction: json['first_time_transaction'] as bool?,
      minimumAmount: json['minimum_amount'] as int?,
      minimumAmountCurrency: json['minimum_amount_currency'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'first_time_transaction': firstTimeTransaction,
      'minimum_amount': minimumAmount,
      'minimum_amount_currency': minimumAmountCurrency,
    };
  }
}

class DiscountedPrice {
  final int amount;
  final String currency;

  const DiscountedPrice({required this.amount, required this.currency});

  factory DiscountedPrice.fromJson(Map<String, dynamic> json) {
    return DiscountedPrice(
      amount: json['amount'] as int,
      currency: json['currency'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'amount': amount, 'currency': currency};
  }
}
