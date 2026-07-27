import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

PangeaToken _makeToken({String content = 'gato'}) => PangeaToken(
  text: PangeaTokenText.fromJson({'content': content, 'offset': 0}),
  lemma: Lemma(text: content, saveVocab: true, form: content),
  pos: 'NOUN',
  morph: const {},
);

/// A minimal in-progress session: one target, nothing answered yet.
AnalyticsPracticeSessionModel _makeSession(ConstructTypeEnum type) =>
    AnalyticsPracticeSessionModel(
      startedAt: DateTime.now().subtract(const Duration(seconds: 90)),
      type: type,
      practiceTargets: [
        AnalyticsPracticeTarget(
          target: PracticeTarget(
            tokens: [_makeToken()],
            exerciseType: PracticeExerciseTypeEnum.lemmaMeaning,
          ),
        ),
      ],
      userL1: 'en',
      userL2: 'es',
    );

void main() {
  final holder = PracticeSessionHolder.instance;

  setUp(holder.end);

  group('PracticeSessionHolder', () {
    test('claim returns the same state for the same type (resume)', () {
      final first = holder.claim(ConstructTypeEnum.vocab);
      final second = holder.claim(ConstructTypeEnum.vocab);
      expect(identical(first, second), isTrue);
    });

    test('claim replaces the held session on type change', () {
      final vocab = holder.claim(ConstructTypeEnum.vocab);
      final grammar = holder.claim(ConstructTypeEnum.morph);
      expect(identical(vocab, grammar), isFalse);
      expect(holder.current, same(grammar));
      expect(grammar.type, ConstructTypeEnum.morph);
    });

    test('a claimed-but-unstarted session is not live', () {
      holder.claim(ConstructTypeEnum.vocab);
      expect(holder.liveType, isNull);
      expect(holder.hasUnfinishedSession, isFalse);
      expect(holder.blocksAnalytics(ConstructTypeEnum.vocab), isFalse);
    });

    test('an in-progress session is live and blocks its own section only', () {
      final state = holder.claim(ConstructTypeEnum.vocab);
      state.sessionController.session = _makeSession(ConstructTypeEnum.vocab);

      expect(holder.liveType, ConstructTypeEnum.vocab);
      expect(holder.hasUnfinishedSession, isTrue);
      expect(holder.blocksAnalytics(ConstructTypeEnum.vocab), isTrue);
      expect(holder.blocksAnalytics(ConstructTypeEnum.morph), isFalse);
    });

    test('a completed session is not live and unblocks analytics', () {
      final state = holder.claim(ConstructTypeEnum.vocab);
      final session = _makeSession(ConstructTypeEnum.vocab);
      state.sessionController.session = session;
      session.finishSession();

      expect(holder.liveType, isNull);
      expect(holder.blocksAnalytics(ConstructTypeEnum.vocab), isFalse);
    });

    test('an errored session is not live', () {
      final state = holder.claim(ConstructTypeEnum.vocab);
      state.sessionController.session = _makeSession(ConstructTypeEnum.vocab);
      state.sessionController.sessionError = Exception('load failed');

      expect(holder.liveType, isNull);
    });

    test('end drops the session and notifies', () {
      final state = holder.claim(ConstructTypeEnum.vocab);
      state.sessionController.session = _makeSession(ConstructTypeEnum.vocab);

      var notified = false;
      holder.addListener(() => notified = true);
      holder.end();

      expect(holder.current, isNull);
      expect(holder.liveType, isNull);
      expect(notified, isTrue);

      // A fresh claim after end starts a new state.
      final fresh = holder.claim(ConstructTypeEnum.vocab);
      expect(identical(fresh, state), isFalse);
    });

    test('resume keeps mid-session progress intact', () {
      final state = holder.claim(ConstructTypeEnum.vocab);
      state.sessionController.session = _makeSession(ConstructTypeEnum.vocab);
      state.progress.value = 0.4;
      state.notifier.selectChoice('some-choice');

      // Simulate the panel closing and reopening: claim again.
      final resumed = holder.claim(ConstructTypeEnum.vocab);
      expect(resumed.progress.value, 0.4);
      expect(resumed.notifier.hasSelectedChoice('some-choice'), isTrue);
      expect(holder.liveType, ConstructTypeEnum.vocab);
    });
  });
}
