class AccessNoticeModel {
  final Map<String, bool> noticesAccepted;

  const AccessNoticeModel({required this.noticesAccepted});

  Map<String, dynamic> toJson() => {"notices_accepted": noticesAccepted};

  static AccessNoticeModel fromJson(Map<String, dynamic> json) {
    return AccessNoticeModel(
      noticesAccepted: json["notices_accepted"] != null
          ? Map<String, bool>.from(json["notices_accepted"])
          : {},
    );
  }

  AccessNoticeModel copyWith({Map<String, bool>? noticesAccepted}) {
    return AccessNoticeModel(
      noticesAccepted: noticesAccepted ?? this.noticesAccepted,
    );
  }
}
