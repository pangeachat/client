import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/l10n/l10n.dart';

enum PanelTypesEnum {
  chats,
  newprivatechat,
  archive,
  archivedroom,
  room,
  session,
  activity,
  course,
  coursepage,
  addcourse,
  addcoursepage,
  settings,
  settingspage,
  analytics,
  vocab,
  grammar,
  review,
  practice;

  Set<PanelTypesEnum> get _roomPanels => {
    PanelTypesEnum.room,
    PanelTypesEnum.session,
    PanelTypesEnum.archivedroom,
  };

  Set<PanelTypesEnum> get _analyticsPanels => {
    PanelTypesEnum.analytics,
    PanelTypesEnum.vocab,
    PanelTypesEnum.grammar,
    PanelTypesEnum.practice,
    PanelTypesEnum.review,
  };

  Set<PanelTypesEnum> get _nonPracticeAnalyticsPanels => {
    PanelTypesEnum.analytics,
    PanelTypesEnum.vocab,
    PanelTypesEnum.grammar,
  };

  Set<PanelTypesEnum> get _settingsPanels => {
    PanelTypesEnum.settings,
    PanelTypesEnum.settingspage,
  };

  Set<PanelTypesEnum> get _addCoursePanels => {
    PanelTypesEnum.addcourse,
    PanelTypesEnum.addcoursepage,
  };

  Set<PanelTypesEnum> get _coursePanels => {
    PanelTypesEnum.course,
    PanelTypesEnum.coursepage,
  };

  Set<PanelTypesEnum> get _courseRelatedPanels => {
    ..._coursePanels,
    ..._addCoursePanels,
  };

  Set<PanelTypesEnum> get _leftChatListPanels => {
    PanelTypesEnum.chats,
    PanelTypesEnum.archive,
  };

  Set<PanelTypesEnum> get _leftChatPanels => {
    PanelTypesEnum.room,
    PanelTypesEnum.archivedroom,
  };

  bool get isRoomPanel => _roomPanels.contains(this);

  bool get isAnalyticsPanel => _analyticsPanels.contains(this);

  /// Non-practice analytics panel (lists of constructs, saved
  /// activity sessions, level details, and construct details pages)
  bool get isNonPracticeAnalyticsPanel =>
      _nonPracticeAnalyticsPanels.contains(this);

  bool get isSettingsPanel => _settingsPanels.contains(this);

  bool get _isAddCoursePanel => _addCoursePanels.contains(this);

  bool get isCoursePanel => _coursePanels.contains(this);

  /// Used to determine if "courses" AppSection should be highlighted in navigation bar
  bool get isCourseRelated => _courseRelatedPanels.contains(this);

  /// Used to determine if "chats" AppSection should be highlighted in navigation bar
  bool get isLeftChatList => _leftChatListPanels.contains(this);

  /// Used to determine if "chats" AppSection should be highlighted in navigation bar
  /// (Secondary to 'courses' section)
  bool get isLeftChat => _leftChatPanels.contains(this);

  /// Courses hub, the course family, the activity plan), as opposed to live
  /// CONTENT (a `room`/`session` conversation). On a single column, a section
  /// and a right panel are peers in the same visual slot, so opening one
  /// closes the other ([setRight]'s / [setSection]'s narrow flags) — while a
  /// live room persists under a right panel (the chat-header avatar loop:
  /// chat → analytics → X → back to the conversation). See
  /// `routing.instructions.md` → Single-column bottom nav.
  bool get isLeftSection =>
      isLeftChatList || isCourseRelated || this == PanelTypesEnum.activity;

  // Narrow chrome (routing.instructions.md → Single-column bottom nav): the
  // section surfaces — the chat list, the Courses/add-course hub, the course
  // family (card + coursepage detail), and the ACTIVITY PLAN (a half-open
  // sheet with the camera on its pin — the Google Maps UX) — ride the nav
  // widget's expandable CAVITY over the map. Only a live chat (a room or a
  // launched session) and the right panels render full-screen over the
  // chrome. The left-panel loop skips the cavity index so it is not also
  // drawn full-screen.
  bool get isCavity => isLeftSection;

  bool get shouldDropOnOpenCourse =>
      isCourseRelated || this == PanelTypesEnum.activity;

  bool get defaultCavityToPeek => {PanelTypesEnum.course}.contains(this);

  // Which rail item's OWN surface the cavity hosts, for the widget's
  // tap-the-active-item toggle. A course sheet / activity plan is neither
  // rail section's surface — the Courses tap must then navigate to the hub
  // instead of toggling (#7537).
  AppSection? get cavitySection {
    if (isLeftChatList) return AppSection.chats;
    if (_isAddCoursePanel) return AppSection.courses;
    return null;
  }

  bool get requireParam => {
    PanelTypesEnum.room,
    PanelTypesEnum.session,
    PanelTypesEnum.archivedroom,
    PanelTypesEnum.activity,
    PanelTypesEnum.coursepage,
    PanelTypesEnum.settingspage,
    PanelTypesEnum.analytics,
    PanelTypesEnum.vocab,
    PanelTypesEnum.grammar,
    PanelTypesEnum.practice,
    PanelTypesEnum.addcoursepage,
  }.contains(this);

  PanelDef get def => switch (this) {
    PanelTypesEnum.chats => ChatsPanelDef(),
    PanelTypesEnum.room => RoomPanelDef(),
    PanelTypesEnum.session => SessionPanelDef(),
    PanelTypesEnum.activity => ActivityPanelDef(),
    PanelTypesEnum.course => CoursePanelDef(),
    PanelTypesEnum.coursepage => CoursePagePanelDef(),
    PanelTypesEnum.addcourse => AddCoursePanelDef(),
    PanelTypesEnum.addcoursepage => AddCoursePagePanelDef(),
    PanelTypesEnum.settings => SettingsPanelDef(),
    PanelTypesEnum.settingspage => SettingsPagePanelDef(),
    PanelTypesEnum.analytics => AnalyticsPanelDef(),
    PanelTypesEnum.vocab => VocabPanelDef(),
    PanelTypesEnum.grammar => GrammarPanelDef(),
    PanelTypesEnum.review => ReviewPanelDef(),
    PanelTypesEnum.practice => PracticePanelDef(),
    PanelTypesEnum.newprivatechat => NewPrivateChatPanelDef(),
    PanelTypesEnum.archive => ArchivePanelDef(),
    PanelTypesEnum.archivedroom => ArchivedRoomPanelDef(),
  };

  String closeButtonLabel(L10n l10n, {String? named}) {
    if (named != null && named.isNotEmpty) return l10n.closeNamed(named);
    switch (this) {
      case PanelTypesEnum.chats:
        return l10n.closeChats;
      case PanelTypesEnum.room:
        return l10n.closeChat;
      case PanelTypesEnum.session:
        return l10n.closeSession;
      case PanelTypesEnum.course:
        return l10n.closeCourse;
      case PanelTypesEnum.coursepage:
        return l10n.closeCoursePage;
      case PanelTypesEnum.addcourse:
        return l10n.closeAddCourse;
      case PanelTypesEnum.addcoursepage:
        return l10n.closeAddCoursePage;
      case PanelTypesEnum.analytics:
        return l10n.closeAnalytics;
      case PanelTypesEnum.vocab:
        return l10n.closeVocabulary;
      case PanelTypesEnum.grammar:
        return l10n.closeGrammar;
      case PanelTypesEnum.practice:
        return l10n.closePractice;
      case PanelTypesEnum.settings:
        return l10n.closeSettings;
      case PanelTypesEnum.archive:
        return l10n.closeArchive;
      default:
        return l10n.close;
    }
  }

  static PanelTypesEnum? fromString(String value) =>
      PanelTypesEnum.values.firstWhereOrNull((v) => v.name == value);
}
