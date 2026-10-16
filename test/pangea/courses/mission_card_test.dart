import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/bold_tonal_button.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../audio_players_stub.dart';

/// The course page's Mission card (#9420): its number, statement, XP ring,
/// Play (or Continue), Practice with the Mission's word count, and the
/// Mission's activities inside it.
void main() {
  setUpAll(AudioPlayersStub.install);
  tearDownAll(AudioPlayersStub.uninstall);

  ActivityPlanModel plan(String id, List<String> words) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: '',
      mode: '',
      objective: '',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a2,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: id,
    learningObjective: '',
    instructions: '',
    vocab: [for (final w in words) Vocab(lemma: w, pos: 'NOUN')],
    activityId: id,
  );

  // "Casa" and "casa" are one word: the count is per lemma, case-folded.
  final group = QuestObjectiveGroup(
    objective: const LearningObjective(id: 'lo-1', objective: 'Can greet.'),
    activities: [
      QuestActivity(activityId: 'a1', plan: plan('a1', ['casa', 'hola'])),
      QuestActivity(activityId: 'a2', plan: plan('a2', ['Casa', 'adiós'])),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onPlay,
    VoidCallback? onPractice,
    String? playLabel,
    String? playDetail,
    Widget? activities,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        // Reduced motion stills Play's pulse, which would otherwise keep a
        // frame scheduled forever.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MissionCard(
              group: group,
              index: 2,
              progress: const MissionProgress(xp: 400, threshold: 1600),
              breakdown: const MissionXpBreakdown(chat: 200, goals: 200),
              onPlay: onPlay,
              onPractice: onPractice ?? () {},
              playLabel: playLabel,
              playDetail: playDetail,
              activities: activities,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names the Mission and its XP toward the star', (tester) async {
    await pump(tester, onPlay: () {});
    expect(find.text('MISSION 2'), findsOneWidget);
    expect(find.text('Can greet.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('400 of 1,600 XP toward this objective'),
      findsOneWidget,
    );
  });

  testWidgets('Play reads Continue with the activity when resuming', (
    tester,
  ) async {
    await pump(
      tester,
      onPlay: () {},
      playLabel: 'Continue',
      playDetail: 'Market day',
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(find.bySemanticsLabel('Continue: Market day'), findsOneWidget);
  });

  testWidgets('Play and Practice are pressable by a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var plays = 0;
    var practices = 0;
    await pump(tester, onPlay: () => plays++, onPractice: () => practices++);

    void press(String label) =>
        tester.semantics.tap(find.semantics.byLabel(label));

    press('Play');
    // Practice says how many words it drills: three, once per lemma.
    press('Practice, 3 words');
    expect(plays, 1);
    expect(practices, 1);
    semantics.dispose();
  });

  testWidgets('with nothing to open, Play is disabled', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    final data = tester
        .getSemantics(find.bySemanticsLabel('Play'))
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('the Mission\'s activities sit inside the card', (tester) async {
    await pump(tester, onPlay: () {});
    expect(find.text('Activities'), findsNothing);

    await pump(tester, onPlay: () {}, activities: const Text('row'));
    expect(
      find.descendant(
        of: find.byType(MissionCard),
        matching: find.text('Activities'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(MissionCard), matching: find.text('row')),
      findsOneWidget,
    );
    // Practice is the shared bold secondary button.
    expect(find.byType(BoldTonalButton), findsOneWidget);
  });
}
