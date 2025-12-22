import 'package:fluffychat/pangea/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/choreo_mode_enum.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension ChoregrapherStateExtension on Choreographer {
  AssistanceStateEnum get assistanceState {
    final isSubscribed =
        MatrixState.pangeaController.subscriptionController.isSubscribed;
    if (isSubscribed == false) return AssistanceStateEnum.noSub;
    if (currentText.trim().isEmpty && itController.sourceText.value == null) {
      return AssistanceStateEnum.noMessage;
    }

    if (errorService.isError) {
      return AssistanceStateEnum.error;
    }

    if (igcController.openMatches.isNotEmpty ||
        (choreoMode == ChoreoModeEnum.it &&
            itController.currentITStep.value?.isFinal != true)) {
      return AssistanceStateEnum.fetched;
    }

    if (isFetching.value) return AssistanceStateEnum.fetching;
    if (igcController.currentText == null &&
        itController.sourceText.value == null) {
      return AssistanceStateEnum.notFetched;
    }
    return AssistanceStateEnum.complete;
  }
}
