enum CheckoutStatus {
  created,
  reused,
  creating;

  factory CheckoutStatus.fromJson(String value) {
    return CheckoutStatus.values.firstWhere((e) => e.name == value);
  }

  String toJson() => name;
}
