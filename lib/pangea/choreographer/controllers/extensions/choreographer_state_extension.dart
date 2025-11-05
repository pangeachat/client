import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choregrapher_user_settings_extension.dart';
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

  bool get canSendMessage {
    // if there's an error, let them send. we don't want to block them from sending in this case
    if (errorService.isError ||
        l2Lang == null ||
        l1Lang == null ||
        timesClicked > 1) {
      return true;
    }

    // if they're in IT mode, don't let them send
    if (itEnabled && isRunningIT) return false;

    // if they've turned off IGC then let them send the message when they want
    if (!isAutoIGCEnabled) return true;

    // if we're in the middle of fetching results, don't let them send
    if (isFetching.value) return false;

    // they're supposed to run IGC but haven't yet, don't let them send
    if (!igcController.hasIGCTextData) {
      return itController.dismissed;
    }

    // if they have relevant matches, don't let them send
    final hasITMatches = igcController.hasOpenITMatches;
    final hasIGCMatches = igcController.hasOpenIGCMatches;
    if ((itEnabled && hasITMatches) || (igcEnabled && hasIGCMatches)) {
      return false;
    }

    // otherwise, let them send
    return true;
  }
}
