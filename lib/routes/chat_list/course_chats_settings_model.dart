class CourseChatsSettingsModel {
  final bool dismissedIntroChat;
  final bool dismissedAnnouncementsChat;

  const CourseChatsSettingsModel({
    this.dismissedIntroChat = false,
    this.dismissedAnnouncementsChat = false,
  });

  Map<String, dynamic> toJson() => {
    'dismissed_intro_chat': dismissedIntroChat,
    'dismissed_announcements_chat': dismissedAnnouncementsChat,
  };

  factory CourseChatsSettingsModel.fromJson(Map<String, dynamic> json) {
    return CourseChatsSettingsModel(
      dismissedIntroChat: json['dismissed_intro_chat'] ?? false,
      dismissedAnnouncementsChat: json['dismissed_announcements_chat'] ?? false,
    );
  }

  CourseChatsSettingsModel copyWith({
    bool? dismissedIntroChat,
    bool? dismissedAnnouncementsChat,
  }) => CourseChatsSettingsModel(
    dismissedIntroChat: dismissedIntroChat ?? this.dismissedIntroChat,
    dismissedAnnouncementsChat:
        dismissedAnnouncementsChat ?? this.dismissedAnnouncementsChat,
  );
}
