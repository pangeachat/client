enum CheckoutStatus {
  created,
  reused,
  creating,
  unknown;

  factory CheckoutStatus.fromJson(String value) {
    return CheckoutStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CheckoutStatus.unknown,
    );
  }

  String toJson() => name;
}
