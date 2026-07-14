class ValidatePromoCodeResponse {
  final bool valid;
  final String? code;
  final String? discountType;
  final double? percentOff;
  final int? amountOff;
  final String? currency;
  final String? couponDuration;
  final PromoRestrictions? restrictions;
  final DiscountedPrice? discountedPrice;
  final int? expiresAt;
  final String? reason;

  const ValidatePromoCodeResponse({
    required this.valid,
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
      valid: json['valid'] as bool,
      code: json['code'] as String?,
      discountType: json['discount_type'] as String?,
      percentOff: (json['percent_off'] as num?)?.toDouble(),
      // Minor-unit amounts arrive as JSON numbers; a serializer may emit
      // 500.0 for 500, so parse via num (consistent with products_v2).
      amountOff: (json['amount_off'] as num?)?.toInt(),
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
      expiresAt: (json['expires_at'] as num?)?.toInt(),
      reason: json['reason'] as String?,
    );
  }

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
      'expires_at': expiresAt,
      'reason': reason,
    };
  }
}

class PromoRestrictions {
  final int? minimumAmount;
  final String? minimumAmountCurrency;
  final bool firstTimeTransaction;

  const PromoRestrictions({
    this.minimumAmount,
    this.minimumAmountCurrency,
    this.firstTimeTransaction = false,
  });

  factory PromoRestrictions.fromJson(Map<String, dynamic> json) {
    return PromoRestrictions(
      minimumAmount: (json['minimum_amount'] as num?)?.toInt(),
      minimumAmountCurrency: json['minimum_amount_currency'] as String?,
      firstTimeTransaction: json['first_time_transaction'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'minimum_amount': minimumAmount,
      'minimum_amount_currency': minimumAmountCurrency,
      'first_time_transaction': firstTimeTransaction,
    };
  }
}

class DiscountedPrice {
  final int amount;
  final String currency;

  const DiscountedPrice({required this.amount, required this.currency});

  factory DiscountedPrice.fromJson(Map<String, dynamic> json) {
    return DiscountedPrice(
      amount: (json['amount'] as num).toInt(),
      currency: json['currency'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'amount': amount, 'currency': currency};
  }
}
