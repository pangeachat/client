import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The accessible name (screen-reader label + tooltip) for a panel's close (X)
/// control. Several panels can be open at once, each with its own X; a bare
/// "Close" is indistinguishable to assistive tech, so the label names the panel
/// it dismisses — derived from [PanelToken.type], the same identity the URL
/// carries (#7274). [named] supplies a dynamic title (e.g. a settings page name)
/// where one token type fronts many surfaces.
String closeButtonLabel(L10n l10n, PanelToken token, {String? named}) {
  if (named != null && named.isNotEmpty) return l10n.closeNamed(named);
  switch (token.type) {
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
