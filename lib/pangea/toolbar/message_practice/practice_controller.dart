import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
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
import 'package:fluffychat/pangea/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/morph_selection.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PracticeController with ChangeNotifier {
  final PangeaMessageEvent pangeaMessageEvent;

  PracticeController(this.pangeaMessageEvent);

  PracticeActivityModel? _activity;

  MessagePracticeMode practiceMode = MessagePracticeMode.noneSelected;

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

  bool isPracticeButtonEmpty(PangeaToken token) {
    final target = practiceTargetForToken(token);

    if (MessagePracticeMode.wordEmoji == practiceMode) {
      if (token.vocabConstructID.userSetEmoji.firstOrNull != null) {
        return false;
      }
      // Keep open even when completed to show emoji
      return target == null;
    }

    if (MessagePracticeMode.wordMorph == practiceMode) {
      // Keep open even when completed to show morph icon
      return target == null;
    }

    return target == null ||
        target.isCompleteByToken(
              token,
              _activity?.morphFeature,
            ) ==
            true;
  }

  Future<Result<PracticeActivityModel>> fetchActivityModel(
    PracticeTarget target,
  ) async {
    final req = MessageActivityRequest(
      userL1: MatrixState.pangeaController.userController.userL1!.langCode,
      userL2: MatrixState.pangeaController.userController.userL2!.langCode,
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

  void updateToolbarMode(MessagePracticeMode mode) {
    selectedChoice = null;
    practiceMode = mode;
    if (practiceMode != MessagePracticeMode.wordMorph) {
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
    practiceMode = MessagePracticeMode.wordMorph;
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

      final constructs = [
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
      ];

      MatrixState
          .pangeaController.matrixState.analyticsDataService.updateService
          .addAnalytics(
        targetId,
        constructs,
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
