class ValidatePromoCodeRequest {
  final String promoCode;

  const ValidatePromoCodeRequest({required this.promoCode});

  String get storageKey => promoCode;

  Map<String, dynamic> toJson() => {"promo_code": promoCode};
}
