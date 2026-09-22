import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_form.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_record_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_choice.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_record.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_record_repo.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// A match choice's state belongs to the word it was tried on. Keyed on the
/// choice's text alone, a choice answered correctly on one word showed as
/// correct under every other word — reported as a wrong answer turning green
/// once the same choice was placed correctly elsewhere (#6259).
void main() {
  PangeaToken token(String content) => PangeaToken(
    text: PangeaTokenText.fromJson({'content': content, 'offset': 0}),
    lemma: Lemma(text: content, saveVocab: true, form: content),
    pos: 'NOUN',
    morph: const {},
  );

  PracticeExerciseChoice choice(String content, PangeaToken forToken) =>
      PracticeExerciseChoice(
        choiceContent: content,
        form: ConstructForm(
          cId: forToken.vocabConstructID,
          form: forToken.text.content,
        ),
      );

  late PangeaToken gato;
  late PangeaToken perro;
  late PracticeTarget target;
  late PracticeRecord record;

  setUp(() {
    gato = token('gato');
    perro = token('perro');
    target = PracticeTarget(
      tokens: [gato, perro],
      exerciseType: PracticeExerciseTypeEnum.wordMeaning,
    );
    // The repo is a static cache keyed by target; start each case empty.
    record = PracticeRecord();
    PracticeRecordRepo.set(target, record);
  });

  void answer(PangeaToken onToken, String text, {required bool correct}) =>
      record.addResponse(
        cId: target.targetTokenConstructID(onToken),
        target: target,
        text: text,
        score: correct ? 1 : 0,
      );

  test('a choice placed on one word does not turn green under another', () {
    answer(gato, 'dog', correct: false);
    answer(perro, 'dog', correct: true);

    final dog = choice('dog', perro);

    expect(
      PracticeRecordController.wasCorrectMatch(target, gato, dog),
      isFalse,
      reason: 'it was the wrong answer for gato and still is',
    );
    expect(
      PracticeRecordController.wasCorrectMatch(target, perro, dog),
      isTrue,
    );
  });

  test('a wrong answer on one word says nothing about another', () {
    answer(gato, 'dog', correct: false);

    expect(
      PracticeRecordController.wasCorrectMatch(
        target,
        perro,
        choice('dog', perro),
      ),
      isNull,
      reason: 'untried on perro, so it carries no verdict there',
    );
  });

  test('an untried choice has no verdict anywhere', () {
    expect(
      PracticeRecordController.wasCorrectMatch(
        target,
        gato,
        choice('cat', gato),
      ),
      isNull,
    );
  });

  group('isChoiceShown', () {
    test('a word\'s own answer stays in its tray after it is placed', () {
      // Grammar holds the right answer up until the learner moves on; the
      // match modes do the same (#6259).
      answer(perro, 'dog', correct: true);
      expect(
        PracticeRecordController.isChoiceShown(
          target,
          perro,
          choice('dog', perro),
        ),
        isTrue,
      );
    });

    test('an answer placed on another word has left this tray', () {
      answer(perro, 'dog', correct: true);
      expect(
        PracticeRecordController.isChoiceShown(
          target,
          gato,
          choice('dog', perro),
        ),
        isFalse,
      );
    });

    test('a choice tried wrongly here is still offered here', () {
      answer(gato, 'dog', correct: false);
      expect(
        PracticeRecordController.isChoiceShown(
          target,
          gato,
          choice('dog', perro),
        ),
        isTrue,
      );
    });

    test('an untried choice is offered', () {
      expect(
        PracticeRecordController.isChoiceShown(
          target,
          gato,
          choice('cat', gato),
        ),
        isTrue,
      );
    });
  });

  test('one answered word completes that word, not the whole target', () {
    // A match target holds every word in the mode. The selected blank counts
    // as answered per word; checking the target would keep its tray live until
    // every word was done.
    answer(perro, 'dog', correct: true);
    expect(PracticeRecordController.isCompleteByToken(target, perro), isTrue);
    expect(PracticeRecordController.isCompleteByTarget(target), isFalse);
  });

  group('isChoicePlaced', () {
    test('is true once the choice has been answered correctly', () {
      answer(perro, 'dog', correct: true);
      expect(
        PracticeRecordController.isChoicePlaced(target, choice('dog', perro)),
        isTrue,
      );
    });

    test('is false for a choice only ever answered wrongly', () {
      answer(gato, 'dog', correct: false);
      expect(
        PracticeRecordController.isChoicePlaced(target, choice('dog', perro)),
        isFalse,
        reason: 'still needs to be offered for the word it belongs to',
      );
    });

    test('is false for an untried choice', () {
      expect(
        PracticeRecordController.isChoicePlaced(target, choice('cat', gato)),
        isFalse,
      );
    });
  });
}
