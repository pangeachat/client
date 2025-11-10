import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/spaces/models/space_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension ChoregrapherUserSettingsExtension on Choreographer {
  LanguageModel? get l2Lang =>
      MatrixState.pangeaController.languageController.activeL2Model();
  String? get l2LangCode => l2Lang?.langCode;
  LanguageModel? get l1Lang =>
      MatrixState.pangeaController.languageController.activeL1Model();
  String? get l1LangCode => l1Lang?.langCode;

  bool get igcEnabled =>
      MatrixState.pangeaController.permissionsController.isToolEnabled(
        ToolSetting.interactiveGrammar,
      );
  bool get itEnabled =>
      MatrixState.pangeaController.permissionsController.isToolEnabled(
        ToolSetting.interactiveTranslator,
      );
  bool get isAutoIGCEnabled =>
      MatrixState.pangeaController.permissionsController.isToolEnabled(
        ToolSetting.autoIGC,
      );
}
