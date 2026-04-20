import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_choice.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_record.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_record_repo.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_target.dart';

class PracticeRecordController {
  static PracticeRecord _recordByTarget(PracticeTarget target) =>
      PracticeRecordRepo.get(target);

  static bool hasAnyResponse(PracticeTarget target) =>
      _recordByTarget(target).responses.isNotEmpty;

  static bool hasResponse(
    PracticeTarget target,
    PangeaToken token,
    String choice,
  ) {
    final cId = target.targetTokenConstructID(token);
    return _recordByTarget(target).alreadyHasMatchResponse(cId, choice);
  }

  static PracticeExerciseRecordResponse? lastResponse(PracticeTarget target) {
    final record = _recordByTarget(target);
    return record.responses.lastOrNull;
  }

  static PracticeExerciseRecordResponse? correctResponse(
    PracticeTarget target,
    PangeaToken token,
  ) {
    final record = _recordByTarget(target);
    return record.responses.firstWhereOrNull(
      (res) => res.cId == target.targetTokenConstructID(token) && res.isCorrect,
    );
  }

  static bool? wasCorrectMatch(
    PracticeTarget target,
    PracticeExerciseChoice choice,
  ) {
    final record = _recordByTarget(target);
    for (final response in record.responses) {
      if (response.text == choice.choiceContent && response.isCorrect) {
        return true;
      }
    }
    for (final response in record.responses) {
      if (response.text == choice.choiceContent) {
        return false;
      }
    }
    return null;
  }

  static bool? wasCorrectChoice(PracticeTarget target, String choice) {
    final record = _recordByTarget(target);
    for (final response in record.responses) {
      if (response.text == choice) {
        return response.isCorrect;
      }
    }
    return null;
  }

  static bool isCompleteByTarget(PracticeTarget target) {
    final record = _recordByTarget(target);
    if (target.exerciseType == PracticeExerciseTypeEnum.morphId) {
      return record.completeResponses > 0;
    }

    return target.tokens.every(
      (t) => record.responses.any(
        (res) => res.cId == target.targetTokenConstructID(t) && res.isCorrect,
      ),
    );
  }

  static bool isCompleteByToken(PracticeTarget target, PangeaToken token) {
    final cId = target.targetTokenConstructID(token);
    return _recordByTarget(
      target,
    ).responses.any((res) => res.cId == cId && res.isCorrect);
  }

  static bool hasAnyCorrectChoices(PracticeTarget target) {
    final record = _recordByTarget(target);
    return record.responses.any((response) => response.isCorrect);
  }

  static bool onSelectChoice(
    String choice,
    PangeaToken token,
    PracticeExerciseModel activity,
  ) {
    final target = activity.practiceTarget;
    final record = _recordByTarget(target);
    final cId = target.targetTokenConstructID(token);
    if (record.alreadyHasMatchResponse(cId, choice)) {
      return false;
    }

    final isCorrect = activity.isCorrect(choice, token);
    record.addResponse(
      cId: cId,
      target: target,
      text: choice,
      score: isCorrect ? 1 : 0,
    );

    return isCorrect;
  }
}
