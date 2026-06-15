class PaymentHistoryRequest {
  final String userID;

  const PaymentHistoryRequest({required this.userID});

  String get storageKey => userID;

  Map<String, dynamic> toJson() => {"userID": userID};
}
