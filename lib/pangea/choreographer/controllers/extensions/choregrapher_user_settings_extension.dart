import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/spaces/models/space_model.dart';

extension ChoregrapherUserSettingsExtension on Choreographer {
  LanguageModel? get l2Lang =>
      pangeaController.languageController.activeL2Model();
  String? get l2LangCode => l2Lang?.langCode;
  LanguageModel? get l1Lang =>
      pangeaController.languageController.activeL1Model();
  String? get l1LangCode => l1Lang?.langCode;

  bool get igcEnabled => pangeaController.permissionsController.isToolEnabled(
        ToolSetting.interactiveGrammar,
        chatController.room,
      );
  bool get itEnabled => pangeaController.permissionsController.isToolEnabled(
        ToolSetting.interactiveTranslator,
        chatController.room,
      );
  bool get isAutoIGCEnabled =>
      pangeaController.permissionsController.isToolEnabled(
        ToolSetting.autoIGC,
        chatController.room,
      );
}
