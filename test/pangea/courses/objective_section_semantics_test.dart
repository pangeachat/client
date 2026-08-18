import 'dart:ui' as ui show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section_scroll_arrow.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// Semantics contract for the activity strip in a Mission row.
///
/// On Flutter web, when the accessibility layer is active, pointer events are
/// dispatched through the semantics DOM tree rather than the render tree. That
/// makes "does this widget have a semantics node" equivalent to "can this widget
/// be clicked at all" on web — which is why these are semantics assertions and
/// not `tester.tap` assertions. A widget-test tap goes through the render tree
/// and passes either way, so it cannot see this class of bug.
///
/// Two directions are pinned here, one per historical regression:
///  - #8011 — a `BlockSemantics` added beside the arrows dropped EVERY card's
///    semantics node in any overflowing row (blocking is not geometric), so no
///    activity card could be opened on web while a chevron was showing.
///  - #7803 — the arrows must still out-rank the cards they overlap, which they
///    do by being painted after the ListView. Pinned as node order.
void main() {
  // The card's image widget reads Environment.cmsApi before it decides whether
  // to fetch anything, so dotenv has to be loaded even though these tests never
  // want a real image.
  setUp(() {
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test.invalid'});
  });

  ActivityPlanModel plan(
    String id,
    String title,
    int participants,
  ) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: '',
      mode: '',
      objective: '',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a2,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: participants,
    ),
    title: title,
    learningObjective: '',
    instructions: '',
    vocab: const [],
    activityId: id,
    // A host outside AppConfig's image allowlist, so the card renders its
    // no-image fallback instead of reaching for the network. Without this the
    // model falls back to a real placeholder URL on the assets host.
    imageURL: 'https://images.test.invalid/$id.png',
  );

  // Ascending participant counts so the widget's own sort keeps this order.
  const titles = ['Alpha Activity', 'Beta Activity', 'Gamma Activity'];
  const objectiveText = 'Can introduce self.';

  QuestObjectiveGroup objectiveGroup() => QuestObjectiveGroup(
    objective: LearningObjective(id: 'lo-1', objective: objectiveText),
    activities: [
      for (var i = 0; i < titles.length; i++)
        QuestActivity(activityId: 'a-$i', plan: plan('a-$i', titles[i], 2 + i)),
    ],
  );

  const cardWidth = 160.0;

  Widget wrap({required double width, void Function(QuestActivity)? onTap}) =>
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: ObjectiveSection(
              group: objectiveGroup(),
              onTap: onTap ?? (_) {},
              userStarsByActivity: (_) => 0,
              hasCompletedActivity: (_) => false,
              liveStateByActivity: (_) => (
                state: null,
                openSessions: 0,
                participants: const <String>[],
                openSlots: 0,
              ),
              availableParticipants: 10,
              progress: null,
              // No vertical padding, so each card gets the height it asks for.
              spacing: 0.0,
              cardWidth: cardWidth,
              cardHeight: 220.0,
            ),
          ),
        ),
      );

  /// Every non-empty semantics label in the live tree, in semantic child order.
  /// Order matters: Flutter web builds its semantics DOM in this order, so a
  /// node listed later sits above an overlapping node listed earlier.
  ///
  /// Anchored on the objective header, which sits outside the activity Stack and
  /// so always has a node, then walked up to the root — the header is the one
  /// node guaranteed to survive whatever the strip below it is doing.
  List<String> labelsInOrder(WidgetTester tester) {
    var root = tester.semantics.find(find.text(objectiveText));
    while (root.parent != null) {
      root = root.parent!;
    }

    final labels = <String>[];
    void visit(SemanticsNode node) {
      if (node.label.isNotEmpty) labels.add(node.label);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(root);
    return labels;
  }

  /// Position of the first node whose label contains [needle], or -1. Cards merge
  /// their title with the participant count into one node ('Alpha Activity\n2'),
  /// so these lookups must be substring matches — an exact `indexOf` silently
  /// returns -1 for every card and makes the ordering assertion below pass
  /// without testing anything.
  int indexOfLabelContaining(List<String> labels, String needle) =>
      labels.indexWhere((label) => label.contains(needle));

  group('ObjectiveSection activity strip semantics', () {
    testWidgets('cards keep their semantics nodes while a scroll arrow is '
        'showing (#8011)', (tester) async {
      final handle = tester.ensureSemantics();
      // 3 x 160 overflows a 360 viewport, so the forward arrow mounts.
      await tester.pumpWidget(wrap(width: 360.0));
      await tester.pumpAndSettle();

      expect(
        find.byType(ObjectiveSectionScrollArrow),
        findsOneWidget,
        reason: 'the overflowing strip should mount its forward arrow',
      );

      final labels = labelsInOrder(tester);
      for (final title in titles) {
        expect(
          indexOfLabelContaining(labels, title),
          isNonNegative,
          reason:
              '$title lost its semantics node while an arrow was showing — on '
              'web that makes the card unclickable. Labels: $labels',
        );
      }
      handle.dispose();
    });

    testWidgets('the arrow node is ordered after the cards it overlaps '
        '(#7803)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(width: 360.0));
      await tester.pumpAndSettle();

      final labels = labelsInOrder(tester);
      final arrowIndex = indexOfLabelContaining(labels, 'Forward');
      expect(
        arrowIndex,
        isNonNegative,
        reason: 'the forward arrow needs its own node. Labels: $labels',
      );

      final lastCardIndex = titles
          .map((t) => indexOfLabelContaining(labels, t))
          .reduce((a, b) => a > b ? a : b);
      // Guard the comparison below against passing on a not-found (-1) card.
      expect(
        lastCardIndex,
        isNonNegative,
        reason: 'the cards need nodes for this ordering check to mean anything',
      );
      expect(
        arrowIndex,
        greaterThan(lastCardIndex),
        reason:
            'the arrow must be painted after the cards so its node sits above '
            'them and takes the tap instead of the card beneath it',
      );
      handle.dispose();
    });

    testWidgets('the arrow node hit-tests as opaque, so it defends its own '
        'strip without a semantics blocker (#7803)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(width: 360.0));
      await tester.pumpAndSettle();

      final arrowNode = tester.getSemantics(
        find.byType(ObjectiveSectionScrollArrow),
      );
      expect(
        arrowNode.hitTestBehavior,
        ui.SemanticsHitTestBehavior.opaque,
        reason:
            'without an opaque semantics hit test, the engine does not '
            'guarantee the arrow\'s DOM element wins pointer events over the '
            'card nodes it overlaps, and #7803 comes back on web',
      );
      handle.dispose();
    });

    testWidgets('no arrow mounts when the strip fits, and the cards still '
        'carry semantics', (tester) async {
      final handle = tester.ensureSemantics();
      // 3 x 160 = 480 fits a 600 viewport.
      await tester.pumpWidget(wrap(width: 600.0));
      await tester.pumpAndSettle();

      expect(find.byType(ObjectiveSectionScrollArrow), findsNothing);
      final labels = labelsInOrder(tester);
      for (final title in titles) {
        expect(
          indexOfLabelContaining(labels, title),
          isNonNegative,
          reason: '$title has no semantics node. Labels: $labels',
        );
      }
      handle.dispose();
    });

    testWidgets('tapping a card opens that activity', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        wrap(width: 360.0, onTap: (a) => tapped.add(a.activityId)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(titles.first));
      await tester.pumpAndSettle();
      expect(tapped, ['a-0']);
    });
  });
}
