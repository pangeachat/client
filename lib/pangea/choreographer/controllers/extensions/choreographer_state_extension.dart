import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choregrapher_user_settings_extension.dart';
import 'package:fluffychat/pangea/choreographer/enums/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/enums/choreo_mode.dart';
import 'package:fluffychat/pangea/choreographer/models/it_step.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';

extension ChoregrapherUserSettingsExtension on Choreographer {
  bool get isITOpen => itController.open;
  bool get isEditingSourceText => itController.editing;
  bool get isITDone => itController.isTranslationDone;
  bool get isRunningIT => choreoMode == ChoreoMode.it && !isITDone;
  List<Continuance>? get itStepContinuances => itController.continuances;

  String? get currentIGCText => igc.currentText;
  PangeaMatchState? get openIGCMatch => igc.openMatch;
  PangeaMatchState? get firstIGCMatch => igc.firstOpenMatch;
  List<PangeaMatchState>? get openIGCMatches => igc.openMatches;
  List<PangeaMatchState>? get closedIGCMatches => igc.closedMatches;
  bool get canShowFirstIGCMatch => igc.canShowFirstMatch;
  bool get hasIGCTextData => igc.hasIGCTextData;

  AssistanceState get assistanceState {
    final isSubscribed = pangeaController.subscriptionController.isSubscribed;
    if (isSubscribed == false) return AssistanceState.noSub;
    if (currentText.isEmpty && sourceText == null) {
      return AssistanceState.noMessage;
    }

    if (igc.hasOpenMatches || isRunningIT) {
      return AssistanceState.fetched;
    }

    if (isFetching) return AssistanceState.fetching;
    if (!igc.hasIGCTextData) return AssistanceState.notFetched;
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
    if (isFetching) return false;

    // they're supposed to run IGC but haven't yet, don't let them send
    if (!igc.hasIGCTextData) {
      return itController.dismissed;
    }

    // if they have relevant matches, don't let them send
    final hasITMatches = igc.hasOpenITMatches;
    final hasIGCMatches = igc.hasOpenIGCMatches;
    if ((itEnabled && hasITMatches) || (igcEnabled && hasIGCMatches)) {
      return false;
    }

    // otherwise, let them send
    return true;
  }
}
