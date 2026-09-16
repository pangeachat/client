import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/features/overlay/overlay_container.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/active_suggestion_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/suggestion_card.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_asssitance_popup_manager.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _FakeRoom extends Fake implements Room {
  @override
  String get id => '!room:server';
}

class _FakeChoreographer extends ChangeNotifier implements Choreographer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestratorController extends Fake
    implements OrchestratorController {
  _FakeOrchestratorController(this.activeSuggestion);

  @override
  final StreamController<ActiveSuggestionModel?> suggestionStream =
      StreamController<ActiveSuggestionModel?>.broadcast();

  @override
  final ActiveSuggestionModel? activeSuggestion;

  @override
  final Room room = _FakeRoom();
}

/// #9074 — the suggestion card used to size itself: a hardcoded 350pt cap and
/// a 250pt scroll box inside it, so it rendered narrower than the composer and
/// scrolled choices that had room to spare. It now fills the popup slot the
/// span card is measured into, and sizes to its content inside it.
void main() {
  const slotWidth = 500.0;
  const slotHeight = 600.0;

  setUp(() {
    // The card reads Environment.isStagingEnvironment in build.
    dotenv.testLoad(mergeWith: <String, String>{});
    MatrixState.pAnyState = PangeaAnyState();
  });

  Widget buildCard(int choiceCount) {
    final suggestion = ActiveSuggestionModel(
      suggestion: OrchestratorRoleSuggestions(
        roleId: 'role',
        suggestions: List.generate(
          choiceCount,
          (i) => OrchestratorSuggestion(
            text: 'Suggestion number $i',
            type: i == 0
                ? OrchestratorSuggestionType.best
                : OrchestratorSuggestionType.distractor,
          ),
        ),
      ),
      basedOnEventId: r'$evt001',
    );

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: OverlayContainer(
            maxWidth: slotWidth,
            maxHeight: slotHeight,
            isScrollable: false,
            cardToShow: SuggestionCard(
              controller: _FakeOrchestratorController(suggestion),
              popupManager: WritingAssistancePopupManager(
                choreographer: _FakeChoreographer(),
                onFeedbackSubmitted: (_) async {},
              ),
              // What ChatController.showSuggestion passes: the slot less the
              // container's padding and border.
              maxHeight: slotHeight - 24.0,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the card fills the slot width instead of a fixed 350', (
    tester,
  ) async {
    await tester.pumpWidget(buildCard(3));
    await tester.pumpAndSettle();

    // The slot less OverlayContainer's 10pt padding and 2pt border per side.
    expect(tester.getSize(find.byType(SuggestionCard)).width, slotWidth - 24.0);
  });

  testWidgets('choices are not clipped into a fixed 250pt scroll box', (
    tester,
  ) async {
    await tester.pumpWidget(buildCard(8));
    await tester.pumpAndSettle();

    // Eight choices need more than the old inner box gave them. With this
    // much room above the input field the card grows to show them all, so
    // there is nothing to scroll.
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, 0.0);
  });
}
