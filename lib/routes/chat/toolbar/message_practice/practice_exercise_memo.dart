import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// Exercises already generated for one message's practice, keyed the way
/// practice records are keyed ([PracticeTarget.storageKey]).
///
/// Generators shuffle their choices and re-pick their distractors, so
/// regenerating a target the learner already saw hands back a different
/// exercise. The memo is what holds an exercise still for as long as the
/// learner can get back to it: leaving a word and returning to it inside one
/// open toolbar shows the exercise they were looking at, not a reshuffled one.
///
/// Deliberately in memory and owned by the practice it belongs to, rather than
/// a repo-level store: an exercise is only ever reused within the practice that
/// generated it, and it dies with that practice. A longer-lived cache serves
/// one learner the same drill — same distractors, same order — across separate
/// sittings, and can outlive corrections made to the lemma content behind it
/// (#8432).
class PracticeExerciseMemo {
  final Map<String, PracticeExerciseModel> _exercises = {};

  PracticeExerciseModel? read(PracticeTarget target) =>
      _exercises[target.storageKey];

  void write(PracticeTarget target, PracticeExerciseModel exercise) =>
      _exercises[target.storageKey] = exercise;

  /// Drops the exercise memoized for [target] so the next fetch regenerates it
  /// — e.g. once the lemma content it was built from has been corrected.
  void remove(PracticeTarget target) => _exercises.remove(target.storageKey);
}
