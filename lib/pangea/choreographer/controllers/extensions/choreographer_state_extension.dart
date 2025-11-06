import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/enums/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/enums/choreo_mode.dart';

extension ChoregrapherUserSettingsExtension on Choreographer {
  bool get isRunningIT {
    return choreoMode == ChoreoMode.it &&
        itController.currentITStep.value?.isFinal != true;
  }

  AssistanceState get assistanceState {
    final isSubscribed = pangeaController.subscriptionController.isSubscribed;
    if (isSubscribed == false) return AssistanceState.noSub;
    if (currentText.isEmpty && itController.sourceText.value == null) {
      return AssistanceState.noMessage;
    }

    if (errorService.isError) {
      return AssistanceState.error;
    }

    if (igcController.hasOpenMatches || isRunningIT) {
      return AssistanceState.fetched;
    }

    if (isFetching.value) return AssistanceState.fetching;
    if (!igcController.hasIGCTextData) return AssistanceState.notFetched;
    return AssistanceState.complete;
  }
}
