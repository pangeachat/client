import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/l10n/l10n.dart';

enum PanelTypesEnum {
  chats,
  newprivatechat,
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

  bool get isRoomPanel =>
      {PanelTypesEnum.room, PanelTypesEnum.session}.contains(this);

  bool get isAnalyticsPanel => {
    PanelTypesEnum.analytics,
    PanelTypesEnum.vocab,
    PanelTypesEnum.grammar,
    PanelTypesEnum.practice,
    PanelTypesEnum.review,
  }.contains(this);

  bool get isCoursePanel => {
    PanelTypesEnum.course,
    PanelTypesEnum.addcourse,
    PanelTypesEnum.addcoursepage,
    PanelTypesEnum.coursepage,
    PanelTypesEnum.activity,
  }.contains(this);

  /// Courses hub, the course family, the activity plan), as opposed to live
  /// CONTENT (a `room`/`session` conversation). On a single column, a section
  /// and a right panel are peers in the same visual slot, so opening one
  /// closes the other ([setRight]'s / [setSection]'s narrow flags) — while a
  /// live room persists under a right panel (the chat-header avatar loop:
  /// chat → analytics → X → back to the conversation). See
  /// `routing.instructions.md` → Single-column bottom nav.
  bool get isLeftSection => {
    PanelTypesEnum.chats,
    PanelTypesEnum.addcourse,
    PanelTypesEnum.addcoursepage,
    PanelTypesEnum.course,
    PanelTypesEnum.coursepage,
    PanelTypesEnum.activity,
  }.contains(this);

  // Narrow chrome (routing.instructions.md → Single-column bottom nav): the
  // section surfaces — the chat list, the Courses/add-course hub, the course
  // family (card + coursepage detail), and the ACTIVITY PLAN (a half-open
  // sheet with the camera on its pin — the Google Maps UX) — ride the nav
  // widget's expandable CAVITY over the map. Only a live chat (a room or a
  // launched session) and the right panels render full-screen over the
  // chrome. The left-panel loop skips the cavity index so it is not also
  // drawn full-screen.
  bool get isCavity => {
    PanelTypesEnum.chats,
    PanelTypesEnum.addcourse,
    PanelTypesEnum.addcoursepage,
    PanelTypesEnum.course,
    PanelTypesEnum.coursepage,
    PanelTypesEnum.activity,
  }.contains(this);

  bool get requireParam => {
    PanelTypesEnum.room,
    PanelTypesEnum.session,
    PanelTypesEnum.activity,
    PanelTypesEnum.coursepage,
    PanelTypesEnum.settingspage,
    PanelTypesEnum.analytics,
    PanelTypesEnum.vocab,
    PanelTypesEnum.grammar,
    PanelTypesEnum.practice,
    PanelTypesEnum.addcoursepage,
  }.contains(this);

  // Which rail item's OWN surface the cavity hosts, for the widget's
  // tap-the-active-item toggle. A course sheet / activity plan is neither
  // rail section's surface — the Courses tap must then navigate to the hub
  // instead of toggling (#7537).
  AppSection? get cavitySection => switch (this) {
    PanelTypesEnum.chats => AppSection.chats,
    PanelTypesEnum.addcourse => AppSection.courses,
    PanelTypesEnum.addcoursepage => AppSection.courses,
    _ => null,
  };

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
      default:
        return l10n.close;
    }
  }

  static PanelTypesEnum? fromString(String value) =>
      PanelTypesEnum.values.firstWhereOrNull((v) => v.name == value);
}
