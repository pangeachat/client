import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';

enum CourseDefaultChatsEnum {
  introductions,
  announcements;

  String get alias => switch (this) {
        CourseDefaultChatsEnum.introductions =>
          SpaceConstants.introductionChatAlias,
        CourseDefaultChatsEnum.announcements =>
          SpaceConstants.announcementsChatAlias,
      };

  String title(L10n l10n) => switch (this) {
        CourseDefaultChatsEnum.introductions => l10n.introductions,
        CourseDefaultChatsEnum.announcements => l10n.announcements,
      };

  String creationTitle(L10n l10n) => switch (this) {
        CourseDefaultChatsEnum.introductions => l10n.introChatTitle,
        CourseDefaultChatsEnum.announcements => l10n.announcementsChatTitle,
      };

  String creationDesc(L10n l10n) => switch (this) {
        CourseDefaultChatsEnum.introductions => l10n.introChatDesc,
        CourseDefaultChatsEnum.announcements => l10n.announcementsChatDesc,
      };
}
