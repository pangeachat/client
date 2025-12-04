import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_choice.dart';
import 'package:fluffychat/pangea/practice_activities/practice_generation_repo.dart';
import 'package:fluffychat/pangea/practice_activities/practice_selection.dart';
import 'package:fluffychat/pangea/practice_activities/practice_selection_repo.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance_input_row/morph_selection.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PracticeController with ChangeNotifier {
  final PangeaMessageEvent pangeaMessageEvent;

  PracticeController(this.pangeaMessageEvent);

  PracticeActivityModel? _activity;

  MessageMode practiceMode = MessageMode.noneSelected;

  MorphSelection? selectedMorph;
  PracticeChoice? selectedChoice;

  PracticeActivityModel? get activity => _activity;

  PracticeSelection? get practiceSelection =>
      pangeaMessageEvent.messageDisplayRepresentation?.tokens != null
          ? PracticeSelectionRepo.get(
              pangeaMessageEvent.eventId,
              pangeaMessageEvent.messageDisplayLangCode,
              pangeaMessageEvent.messageDisplayRepresentation!.tokens!,
            )
          : null;

  bool get isTotallyDone =>
      isPracticeActivityDone(ActivityTypeEnum.emoji) &&
      isPracticeActivityDone(ActivityTypeEnum.wordMeaning) &&
      isPracticeActivityDone(ActivityTypeEnum.wordFocusListening) &&
      isPracticeActivityDone(ActivityTypeEnum.morphId);

  bool isPracticeActivityDone(ActivityTypeEnum activityType) =>
      practiceSelection?.activities(activityType).every((a) => a.isComplete) ==
      true;

  Future<Result<PracticeActivityModel>> fetchActivityModel(
    PracticeTarget target,
  ) async {
    final req = MessageActivityRequest(
      userL1: MatrixState.pangeaController.languageController.userL1!.langCode,
      userL2: MatrixState.pangeaController.languageController.userL2!.langCode,
      userGender: MatrixState
          .pangeaController.userController.profile.userSettings.gender,
      messageText: pangeaMessageEvent.messageDisplayText,
      messageTokens:
          pangeaMessageEvent.messageDisplayRepresentation?.tokens ?? [],
      activityQualityFeedback: null,
      targetTokens: target.tokens,
      targetType: target.activityType,
      targetMorphFeature: target.morphFeature,
    );

    final result = await PracticeRepo.getPracticeActivity(req);
    if (result.isValue) {
      _activity = result.result;
    }

    return result;
  }

  PracticeTarget? practiceTargetForToken(PangeaToken token) {
    if (practiceMode.associatedActivityType == null) return null;
    return practiceSelection
        ?.activities(practiceMode.associatedActivityType!)
        .firstWhereOrNull((a) => a.tokens.contains(token));
  }

  void updateToolbarMode(MessageMode mode) {
    selectedChoice = null;
    practiceMode = mode;
    if (practiceMode != MessageMode.wordMorph) {
      selectedMorph = null;
    }
    notifyListeners();
  }

  void onChoiceSelect(PracticeChoice? choice, [bool force = false]) {
    if (_activity == null) return;
    if (selectedChoice == choice && !force) {
      selectedChoice = null;
    } else {
      selectedChoice = choice;
    }
    notifyListeners();
  }

  void onSelectMorph(MorphSelection newMorph) {
    practiceMode = MessageMode.wordMorph;
    selectedMorph = newMorph;
    notifyListeners();
  }

  void onMatch(PangeaToken token, PracticeChoice choice) {
    if (_activity == null) return;

    final isCorrect = _activity!.activityType == ActivityTypeEnum.morphId
        ? _activity!.onMultipleChoiceSelect(token, choice)
        : _activity!.onMatch(token, choice);

    final targetId =
        "message-token-${token.text.uniqueKey}-${pangeaMessageEvent.eventId}";

    // we don't take off points for incorrect emoji matches
    if (_activity!.activityType != ActivityTypeEnum.emoji || isCorrect) {
      final constructUseType = _activity!.practiceTarget.record.responses.last
          .useType(_activity!.activityType);

      MatrixState.pangeaController.putAnalytics.setState(
        AnalyticsStream(
          eventId: pangeaMessageEvent.eventId,
          roomId: pangeaMessageEvent.room.id,
          constructs: [
            OneConstructUse(
              useType: constructUseType,
              lemma: token.lemma.text,
              constructType: ConstructTypeEnum.vocab,
              metadata: ConstructUseMetaData(
                roomId: pangeaMessageEvent.room.id,
                timeStamp: DateTime.now(),
                eventId: pangeaMessageEvent.eventId,
              ),
              category: token.pos,
              // in the case of a wrong answer, the cId doesn't match the token
              form: token.text.content,
              xp: constructUseType.pointValue,
            ),
          ],
          targetID: targetId,
        ),
      );
    }

    if (isCorrect) {
      if (_activity!.activityType == ActivityTypeEnum.emoji) {
        choice.form.cId.setUserLemmaInfo(
          choice.form.cId.userLemmaInfo.copyWith(
            emojis: [choice.choiceContent],
          ),
        );
      }

      if (_activity!.activityType == ActivityTypeEnum.wordMeaning) {
        choice.form.cId.setUserLemmaInfo(
          choice.form.cId.userLemmaInfo.copyWith(
            meaning: choice.choiceContent,
          ),
        );
      }
    }

    notifyListeners();
  }
}
