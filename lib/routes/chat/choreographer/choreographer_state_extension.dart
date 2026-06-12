import 'package:fluffychat/routes/chat/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension ChoregrapherStateExtension on Choreographer {
  AssistanceStateEnum get assistanceState {
    final isSubscribed =
        MatrixState.pangeaController.subscriptionController.isSubscribed;

    if (isSubscribed == false) return AssistanceStateEnum.noSub;
    if (currentText.trim().isEmpty) {
      if (orchestratorController.activeSuggestion != null) {
        return AssistanceStateEnum.suggesting;
      }
      return AssistanceStateEnum.noMessage;
    }

    if (errorService.blockWritingAssistance) {
      return AssistanceStateEnum.error;
    }

    if (igcController.openMatches.isNotEmpty) {
      return AssistanceStateEnum.fetched;
    }

    if (isFetching.value) return AssistanceStateEnum.fetching;
    if (igcController.currentText == null) {
      if (orchestratorController.hasAcceptedSuggestion) {
        return AssistanceStateEnum.suggestionComplete;
      }
      return AssistanceStateEnum.notFetched;
    }
    return AssistanceStateEnum.igcComplete;
  }
}
