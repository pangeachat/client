import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/overlay/overlay_position.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/active_suggestion_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/suggestion_card.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_assistance_popup.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_asssitance_popup_manager.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _FakeChoreographer extends ChangeNotifier implements Choreographer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestratorController extends Fake
    implements OrchestratorController {
  @override
  final StreamController<ActiveSuggestionModel?> suggestionStream =
      StreamController<ActiveSuggestionModel?>.broadcast();

  @override
  ActiveSuggestionModel? get activeSuggestion => null;
}

/// #8980 — writing assistance stopped putting its card on screen and never
/// recovered until the page was reloaded.
///
/// [WritingAssistancePopupManager] recorded `open` before it knew whether an
/// overlay had mounted, and the ONLY thing that ever moves it back to `closed`
/// is the card's own [WritingAssistancePopup] being disposed. So a card that
/// never mounted left the manager certain one was up for the life of the chat:
/// `showNextMatch` skipped its open block on `isOpen` (while still moving the
/// active match, so highlights kept answering taps with no card), and the
/// `close()` a writing assistance run awaits never completed.
void main() {
  const targetId = 'input_text_field';
  const cardKey = ValueKey('span-card');

  late WritingAssistancePopupManager manager;

  setUp(() {
    MatrixState.pAnyState = PangeaAnyState();
    manager = WritingAssistancePopupManager(
      choreographer: _FakeChoreographer(),
      onFeedbackSubmitted: (_) async {},
    );
  });

  /// The real `ChatController.showNextMatch` open block, trimmed to the parts
  /// that decide whether an overlay mounts.
  void showSpanCard(BuildContext context) => manager.open(
    context,
    openOverlay: (overlayKey) => OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: WritingAssistancePopup(
        manager,
        child: const SizedBox(key: cardKey, width: 200, height: 100),
      ),
      displayDetails: PositionedOverlayDisplayDetails(
        overlayKey: overlayKey,
        maxHeight: 200,
        maxWidth: 200,
        transformTargetId: targetId,
        ignorePointer: true,
        blockPointerThrough: true,
        isScrollable: false,
      ),
      overlayPosition: OverlayPosition.above,
    ),
  );

  /// Stands in for the composer: the target the card follows, and the
  /// GlobalKey `showPositionedCard` measures to size it. The real input row
  /// puts that key on the NON-recording branch of a ternary, so it is absent
  /// while the learner is recording a voice message.
  Widget buildHarness({bool mountComposer = true}) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Stack(
          children: [
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: CompositedTransformTarget(
                link: MatrixState.pAnyState.layerLinkAndKey(targetId).link,
                child: mountComposer
                    ? SizedBox(
                        key: MatrixState.pAnyState
                            .layerLinkAndKey(targetId)
                            .key,
                        height: 48,
                      )
                    : const SizedBox(height: 48),
              ),
            ),
            Positioned(
              top: 0,
              child: TextButton(
                onPressed: () => showSpanCard(context),
                child: const Text('check'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> pressCheck(WidgetTester tester) async {
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();
  }

  /// `close()` completes on the frame that disposes the card, so it can only
  /// be awaited across a pump — never before one.
  Future<bool> closeAndPump(WidgetTester tester) async {
    var closed = false;
    unawaited(manager.close().then((_) => closed = true));
    await tester.pumpAndSettle();
    return closed;
  }

  testWidgets('the card opens, closes, and opens again', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    await pressCheck(tester);
    expect(find.byKey(cardKey), findsOneWidget);
    expect(manager.isOpen, isTrue);

    expect(await closeAndPump(tester), isTrue);
    expect(find.byKey(cardKey), findsNothing);
    expect(manager.isOpen, isFalse);

    await pressCheck(tester);
    expect(find.byKey(cardKey), findsOneWidget);
  });

  testWidgets('an overlay that blocks the card does not wedge the manager', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    // What a tutorial sequence puts up, and the only thing in the app that
    // does: it cannot be popped, so `open`'s own `closeAllOverlays` cannot
    // clear it, and `PangeaAnyState.openOverlay` refuses every overlay while
    // it is there.
    final blocker = OverlayEntry(builder: (_) => const SizedBox.shrink());
    MatrixState.pAnyState.openOverlay(
      blocker,
      tester.element(find.text('check')),
      overlayKey: 'tutorial-sequence',
      canPop: false,
      blockOverlay: true,
    );
    await tester.pumpAndSettle();

    await pressCheck(tester);
    expect(find.byKey(cardKey), findsNothing, reason: 'blocked, as expected');
    expect(
      manager.isOpen,
      isFalse,
      reason: 'nothing mounted, so nothing is open',
    );

    // The tutorial ends, and writing assistance works again.
    MatrixState.pAnyState.closeOverlay('tutorial-sequence');
    await tester.pumpAndSettle();

    await pressCheck(tester);
    expect(find.byKey(cardKey), findsOneWidget);
    expect(await closeAndPump(tester), isTrue, reason: 'close() completes');
  });

  testWidgets('a composer that cannot be measured does not wedge the manager', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(mountComposer: false));
    await tester.pumpAndSettle();

    await pressCheck(tester);
    expect(find.byKey(cardKey), findsNothing);
    expect(
      manager.isOpen,
      isFalse,
      reason: 'nothing mounted, so nothing is open',
    );

    // The recording ends and the composer is back.
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    await pressCheck(tester);
    expect(find.byKey(cardKey), findsOneWidget);
    expect(await closeAndPump(tester), isTrue, reason: 'close() completes');
  });

  testWidgets('an empty suggestion card still mounts the popup wrapper', (
    tester,
  ) async {
    // The wrapper is the manager's only close signal, so a build that returns
    // in place of it — which is what this card did with no active suggestion —
    // leaves the manager certain a card is up forever.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: SuggestionCard(
          overlayKey: 'writing-assistance-popup-overlay',
          controller: _FakeOrchestratorController(),
          popupManager: manager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WritingAssistancePopup), findsOneWidget);
  });
}
