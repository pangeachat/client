import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/active_suggestion_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/routes/chat/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer_error_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer_state_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_response_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/segmented_circular_progress.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/start_igc_button.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The writing assistance ring's segments in each state: five while there is
/// nothing to report, one per match, one solid green ring when a check finds
/// nothing or a suggestion is taken, and two while a suggestion waits.
/// Colour and brightness per match are left out on purpose: the doc and the
/// app disagree on them, and that is an open question, not a fact to pin.
/// See writing-assistance.instructions.md § The experience.
void main() {
  late _FakeChoreographer choreographer;
  late BuildContext context;

  setUp(() {
    MatrixState.pangeaController = _FakePangeaController();
    choreographer = _FakeChoreographer();
  });

  tearDown(() => choreographer.dispose());

  Future<void> pumpRing(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              final state = choreographer.assistanceState;
              return StartIGCButton(
                onPressed: () {},
                choreographer: choreographer,
                initialState: state,
                initialForegroundColor: state.stateColor(c),
              );
            },
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the fetching spin repeats until the fetch ends.
    await tester.pump(const Duration(seconds: 1));
  }

  List<Segment> segments(WidgetTester tester) => tester
      .widget<SegmentedCircularProgress>(find.byType(SegmentedCircularProgress))
      .segments;

  SpanData span(int offset) => SpanData(
    message: null,
    shortMessage: null,
    choices: [SpanChoice(value: 'geht', type: SpanChoiceTypeEnum.suggestion)],
    offset: offset,
    length: 4,
    fullText: 'gehe gehe',
    type: ReplacementTypeEnum.verbConjugation,
    rule: null,
  );

  void loadMatches(List<SpanData> spans) {
    choreographer.currentText = 'gehe gehe';
    choreographer.igcController.loadResponse(
      IGCResponseModel(
        originalInput: 'gehe gehe',
        fullTextCorrection: null,
        matches: [
          for (final s in spans)
            PangeaMatch(match: s, status: PangeaMatchStatusEnum.open),
        ],
        userL1: 'en',
        userL2: 'de',
      ),
    );
  }

  testWidgets('an empty composer shows five grey segments', (tester) async {
    await pumpRing(tester);

    expect(choreographer.assistanceState, AssistanceStateEnum.noMessage);
    final ring = segments(tester);
    expect(ring, hasLength(5));
    expect(ring.map((s) => s.color).toSet(), {
      Theme.of(context).colorScheme.outline,
    });
  });

  testWidgets('the ring has one segment per match', (tester) async {
    loadMatches([span(0), span(5)]);
    await pumpRing(tester);

    expect(choreographer.assistanceState, AssistanceStateEnum.fetched);
    expect(segments(tester), hasLength(2));
  });

  testWidgets('a check that finds nothing shows one solid green ring', (
    tester,
  ) async {
    loadMatches([]);
    await pumpRing(tester);

    expect(choreographer.assistanceState, AssistanceStateEnum.igcComplete);
    final ring = segments(tester);
    expect(ring, hasLength(1));
    expect(ring.single.color, Theme.of(context).pangea.successGraphic);
  });

  testWidgets('a re-check clears the old segments while it runs', (
    tester,
  ) async {
    loadMatches([span(0), span(5)]);
    await pumpRing(tester);
    expect(segments(tester), hasLength(2));

    choreographer.igcController
      ..clearMatches()
      ..clearCurrentText();
    choreographer.isFetching.value = true;
    choreographer.notifyListeners();
    // One frame to start the segment animation, then past its end.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(choreographer.assistanceState, AssistanceStateEnum.fetching);
    expect(segments(tester), hasLength(5));
    // The check mark hides while the ring spins.
    expect(AssistanceStateEnum.fetching.showIcon, isFalse);
  });

  testWidgets('clearing the message returns the ring to grey', (tester) async {
    loadMatches([span(0), span(5)]);
    await pumpRing(tester);

    choreographer.igcController
      ..clearMatches()
      ..clearCurrentText();
    choreographer.currentText = '';
    choreographer.notifyListeners();
    await tester.pumpAndSettle();

    expect(choreographer.assistanceState, AssistanceStateEnum.noMessage);
    final ring = segments(tester);
    expect(ring, hasLength(5));
    expect(ring.map((s) => s.color).toSet(), {
      Theme.of(context).colorScheme.outline,
    });
  });

  testWidgets('a waiting suggestion shows two segments', (tester) async {
    choreographer.orchestrator.activeSuggestion = _suggestion();
    await pumpRing(tester);

    expect(choreographer.assistanceState, AssistanceStateEnum.suggesting);
    final ring = segments(tester);
    expect(ring, hasLength(2));
    expect(ring.map((s) => s.color).toSet(), {
      Theme.of(context).colorScheme.primary,
    });
  });

  testWidgets('an accepted suggestion shows one solid green ring', (
    tester,
  ) async {
    choreographer.orchestrator.activeSuggestion = _suggestion(accepted: true);
    choreographer.currentText = 'Hallo';
    await pumpRing(tester);

    expect(
      choreographer.assistanceState,
      AssistanceStateEnum.suggestionComplete,
    );
    final ring = segments(tester);
    expect(ring, hasLength(1));
    expect(ring.single.color, Theme.of(context).pangea.successGraphic);
  });
}

ActiveSuggestionModel _suggestion({bool accepted = false}) {
  const choice = OrchestratorSuggestion(
    text: 'Hallo',
    type: OrchestratorSuggestionType.best,
  );
  return ActiveSuggestionModel(
    suggestion: _FakeRoleSuggestions(),
    basedOnEventId: r'$turn',
    shuffledChoices: const [choice],
    acceptedChoice: accepted ? choice : null,
  );
}

class _FakePangeaController implements PangeaController {
  @override
  final SubscriptionController subscriptionController =
      _FakeSubscriptionController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSubscriptionController implements SubscriptionController {
  @override
  bool get showSubscriptionGatedContent => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The ring reads the choreographer's text, fetch flag, match list, error
/// state and suggestion, and rebuilds when it notifies. Nothing here runs
/// writing assistance; the match list is filled the way a response would.
class _FakeChoreographer extends ChangeNotifier implements Choreographer {
  @override
  String currentText = '';

  @override
  final ValueNotifier<bool> isFetching = ValueNotifier(false);

  @override
  final IgcController igcController = IgcController((_) {}, () {});

  @override
  final ChoreographerErrorController errorService =
      ChoreographerErrorController();

  final _FakeOrchestratorController orchestrator =
      _FakeOrchestratorController();

  @override
  OrchestratorController get orchestratorController => orchestrator;

  @override
  void dispose() {
    igcController.dispose();
    orchestrator.suggestionStream.close();
    isFetching.dispose();
    errorService.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeOrchestratorController implements OrchestratorController {
  @override
  final StreamController<ActiveSuggestionModel?> suggestionStream =
      StreamController.broadcast();

  @override
  ActiveSuggestionModel? activeSuggestion;

  @override
  bool get hasAcceptedSuggestion => activeSuggestion?.acceptedChoice != null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRoleSuggestions implements OrchestratorRoleSuggestions {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
