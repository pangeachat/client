class NotificationsSettingsModel {
  final bool enableEmailNotifs;

  const NotificationsSettingsModel({this.enableEmailNotifs = false});

  Map<String, dynamic> toJson() {
    return {'enable_email_notifs': enableEmailNotifs};
  }

  factory NotificationsSettingsModel.fromJson(Map<String, dynamic> json) {
    return NotificationsSettingsModel(
      enableEmailNotifs: json['enable_email_notifs'] ?? false,
    );
  }

  NotificationsSettingsModel copyWith({bool? enableEmailNotifs}) {
    return NotificationsSettingsModel(
      enableEmailNotifs: enableEmailNotifs ?? this.enableEmailNotifs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is NotificationsSettingsModel &&
        other.enableEmailNotifs == enableEmailNotifs;
  }

  @override
  int get hashCode => enableEmailNotifs.hashCode;
}
