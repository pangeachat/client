import 'package:fluffychat/pangea/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/choreo_mode_enum.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';

extension ChoregrapherUserSettingsExtension on Choreographer {
  bool get isRunningIT {
    return choreoMode == ChoreoModeEnum.it &&
        itController.currentITStep.value?.isFinal != true;
  }

  AssistanceStateEnum get assistanceState {
    final isSubscribed = pangeaController.subscriptionController.isSubscribed;
    if (isSubscribed == false) return AssistanceStateEnum.noSub;
    if (currentText.isEmpty && itController.sourceText.value == null) {
      return AssistanceStateEnum.noMessage;
    }

    if (errorService.isError) {
      return AssistanceStateEnum.error;
    }

    if (igcController.hasOpenMatches || isRunningIT) {
      return AssistanceStateEnum.fetched;
    }

    if (isFetching.value) return AssistanceStateEnum.fetching;
    if (!igcController.hasIGCTextData) return AssistanceStateEnum.notFetched;
    return AssistanceStateEnum.complete;
  }
}
