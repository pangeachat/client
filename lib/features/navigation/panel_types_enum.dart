import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/panel_registry.dart';

enum PanelTypesEnum {
  chats,
  room,
  session,
  activity,
  course,
  coursepage,
  addcourse,
  settings,
  settingspage,
  analytics,
  vocab,
  grammar,
  review,
  practice;

  PanelDef get def => switch (this) {
    PanelTypesEnum.chats => ChatsPanelDef(),
    PanelTypesEnum.room => RoomPanelDef(),
    PanelTypesEnum.session => SessionPanelDef(),
    PanelTypesEnum.activity => ActivityPanelDef(),
    PanelTypesEnum.course => CoursePanelDef(),
    PanelTypesEnum.coursepage => CoursePagePanelDef(),
    PanelTypesEnum.addcourse => AddCoursePanelDef(),
    PanelTypesEnum.settings => SettingsPanelDef(),
    PanelTypesEnum.settingspage => SettingsPagePanelDef(),
    PanelTypesEnum.analytics => AnalyticsPanelDef(),
    PanelTypesEnum.vocab => VocabPanelDef(),
    PanelTypesEnum.grammar => GrammarPanelDef(),
    PanelTypesEnum.review => ReviewPanelDef(),
    PanelTypesEnum.practice => PracticePanelDef(),
  };

  static PanelTypesEnum? fromString(String value) =>
      PanelTypesEnum.values.firstWhereOrNull((v) => v.name == value);
}
