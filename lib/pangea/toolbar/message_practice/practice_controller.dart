import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_choice.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_generation_repo.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_selection.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_selection_repo.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_target.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/morph_selection.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_record_controller.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PracticeController with ChangeNotifier {
  final PangeaMessageEvent pangeaMessageEvent;

  PracticeController(this.pangeaMessageEvent) {
    _fetchPracticeSelection();
  }

  PracticeExerciseModel? _activity;

  MessagePracticeMode _practiceMode = MessagePracticeMode.noneSelected;

  MorphSelection? _selectedMorph;
  PracticeExerciseChoice? _selectedChoice;

  PracticeSelection? practiceSelection;

  MessagePracticeMode get practiceMode => _practiceMode;
  MorphSelection? get selectedMorph => _selectedMorph;
  PracticeExerciseChoice? get selectedChoice => _selectedChoice;

  PracticeTarget? get currentTarget {
    final activityType = _practiceMode.associatedActivityType;
    if (activityType == null) return null;
    if (activityType == PracticeExerciseTypeEnum.morphId) {
      if (_selectedMorph == null) return null;
      return practiceSelection?.getMorphTarget(
        _selectedMorph!.token,
        _selectedMorph!.morph,
      );
    }
    return practiceSelection?.getTarget(activityType);
  }

  bool get showChoiceShimmer {
    if (_activity == null) return false;
    if (_activity is MorphMatchPracticeExerciseModel) {
      return _selectedMorph != null &&
          !PracticeRecordController.hasAnyResponse(_activity!.practiceTarget);
    }

    return _selectedChoice == null &&
        !PracticeRecordController.hasAnyCorrectChoices(
          _activity!.practiceTarget,
        );
  }

  bool get isTotallyDone =>
      isPracticeSessionDone(PracticeExerciseTypeEnum.emoji) &&
      isPracticeSessionDone(PracticeExerciseTypeEnum.wordMeaning) &&
      isPracticeSessionDone(PracticeExerciseTypeEnum.wordFocusListening) &&
      isPracticeSessionDone(PracticeExerciseTypeEnum.morphId);

  bool get isCurrentPracticeSessionDone {
    final activityType = _practiceMode.associatedActivityType;
    if (activityType == null) return false;
    return isPracticeSessionDone(activityType);
  }

  bool? wasCorrectMatch(PracticeExerciseChoice choice) {
    if (_activity == null) return false;
    return PracticeRecordController.wasCorrectMatch(
      _activity!.practiceTarget,
      choice,
    );
  }

  bool? wasCorrectChoice(String choice) {
    if (_activity == null) return false;
    return PracticeRecordController.wasCorrectChoice(
      _activity!.practiceTarget,
      choice,
    );
  }

  bool isPracticeSessionDone(PracticeExerciseTypeEnum activityType) =>
      practiceSelection
          ?.activities(activityType)
          .every((a) => PracticeRecordController.isCompleteByTarget(a)) ==
      true;

  bool isActivityCompleteByToken(PangeaToken token) {
    final target = practiceTargetForToken(token);
    if (target == null) return false;
    return PracticeRecordController.isCompleteByTarget(target);
  }

  bool isPracticeButtonEmpty(PangeaToken token) {
    final target = practiceTargetForToken(token);
    switch (_practiceMode) {
      // Keep open when completed if emoji assigned
      case MessagePracticeMode.wordEmoji:
        if (token.vocabConstructID.userSetEmoji != null) return false;
        return target == null;
      // Keep open when completed to show morph icon
      case MessagePracticeMode.wordMorph:
        return target == null;
      default:
        return target == null ||
            PracticeRecordController.isCompleteByToken(target, token);
    }
  }

  PracticeTarget? practiceTargetForToken(PangeaToken token) {
    if (_practiceMode.associatedActivityType == null) return null;
    return practiceSelection
        ?.activities(_practiceMode.associatedActivityType!)
        .firstWhereOrNull((a) => a.tokens.contains(token));
  }

  void updateToolbarMode(MessagePracticeMode mode) {
    _selectedChoice = null;
    _practiceMode = mode;
    if (_practiceMode != MessagePracticeMode.wordMorph) {
      _selectedMorph = null;
    }
    notifyListeners();
  }

  void updatePracticeMorph(MorphSelection newMorph) {
    _practiceMode = MessagePracticeMode.wordMorph;
    _selectedMorph = newMorph;
    notifyListeners();
  }

  void onChoiceSelect(PracticeExerciseChoice? choice) {
    if (_activity == null) return;
    if (_selectedChoice == choice) {
      _selectedChoice = null;
    } else {
      _selectedChoice = choice;
    }
    notifyListeners();
  }

  void onMatch(PangeaToken token, PracticeExerciseChoice choice) {
    final activity = _activity;
    if (activity == null) return;

    final target = activity.practiceTarget;
    final isRepeatedResponse = PracticeRecordController.hasResponse(
      target,
      token,
      choice.choiceContent,
    );
    if (isRepeatedResponse) return;

    final isCorrect = PracticeRecordController.onSelectChoice(
      choice.choiceContent,
      token,
      activity,
    );

    final targetId =
        "message-token-${token.text.uniqueKey}-${pangeaMessageEvent.eventId}";

    final updateService = MatrixState
        .pangeaController
        .matrixState
        .analyticsDataService
        .updateService;

    // we don't take off points for incorrect emoji matches
    if (activity is! EmojiPracticeExerciseModel || isCorrect) {
      final l2 =
          MatrixState.pangeaController.userController.userL2?.langCodeShort;
      if (l2 == null) {
        ErrorHandler.logError(
          e: "User L2 is null when trying to log construct use for token ${token.text.content} in practice exercise",
          data: {
            "eventId": pangeaMessageEvent.eventId,
            "token": token.text.content,
            "activityType": activity.exerciseType.toString(),
          },
        );
        return;
      }

      final constructUseType = PracticeRecordController.lastResponse(
        activity.practiceTarget,
      )!.useType(activity.exerciseType);

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

      updateService.addAnalytics(targetId, constructs, l2);
    }

    if (isCorrect) {
      if (activity is EmojiPracticeExerciseModel) {
        updateService.setLemmaInfo(
          choice.form.cId,
          emoji: choice.choiceContent,
        );
      }

      if (activity is LemmaMeaningPracticeExerciseModel) {
        updateService.setLemmaInfo(
          choice.form.cId,
          meaning: choice.choiceContent,
        );
      }
    }

    if (activity is LemmaMeaningPracticeExerciseModel ||
        activity is EmojiPracticeExerciseModel) {
      TtsController.tryToSpeak(
        token.text.content,
        langCode: MatrixState.pangeaController.userController.userL2!.langCode,
        pos: token.pos,
        morph: token.morph.map((k, v) => MapEntry(k.name, v)),
      );
    }

    notifyListeners();
  }

  Future<void> _fetchPracticeSelection() async {
    if (pangeaMessageEvent.messageDisplayRepresentation?.tokens == null) return;
    practiceSelection = await PracticeSelectionRepo.get(
      pangeaMessageEvent.eventId,
      pangeaMessageEvent.messageDisplayLangCode,
      pangeaMessageEvent.messageDisplayRepresentation!.tokens!,
    );
  }

  Future<Result<PracticeExerciseModel>> fetchActivityModel(
    PracticeTarget target,
  ) async {
    final req = MessagePracticeExerciseRequest(
      userL1: MatrixState.pangeaController.userController.userL1!.langCode,
      userL2: MatrixState.pangeaController.userController.userL2!.langCode,
      exerciseQualityFeedback: null,
      target: target,
    );

    final result = await PracticeRepo.getPracticeExercise(
      req,
      messageInfo: pangeaMessageEvent.event.content,
    );
    if (result.isValue) {
      _activity = result.result;
    }

    return result;
  }
}
