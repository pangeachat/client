class AccessNoticeModel {
  final Map<String, bool> noticesShown;

  const AccessNoticeModel({required this.noticesShown});

  Map<String, dynamic> toJson() => {"notices_shown": noticesShown};

  static AccessNoticeModel fromJson(Map<String, dynamic> json) {
    return AccessNoticeModel(
      noticesShown: json["notices_shown"] != null
          ? Map<String, bool>.from(json["notices_shown"])
          : {},
    );
  }

  AccessNoticeModel copyWith({Map<String, bool>? noticesShown}) {
    return AccessNoticeModel(noticesShown: noticesShown ?? this.noticesShown);
  }
}
