import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Profile;

import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_card.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_asssitance_popup_manager.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #8964 — the card must show whichever match is active.
///
/// The learner navigates between matches by tapping the highlights in the input
/// field, and each tap sets `IgcController.activeMatch`. The card cannot take
/// its rebuild cue from `matchUpdateStream`: that fires on a match's STATUS
/// changing, and a status changes exactly once, `open` -> `viewed`, the first
/// time the match is opened. So the first tap on a highlight moved the card and
/// every later tap on it did not — the input field's highlight followed the
/// learner while the card went on showing the previous match, and its buttons
/// went on editing that match's span.
///
/// See writing-assistance.instructions.md § Interaction Model.
void main() {
  late IgcController igc;

  SpanData span({
    required String choice,
    required String feedback,
    required int offset,
  }) => SpanData(
    message: null,
    shortMessage: null,
    choices: [
      SpanChoice(
        value: choice,
        type: SpanChoiceTypeEnum.suggestion,
        feedback: feedback,
      ),
    ],
    offset: offset,
    length: 4,
    fullText: 'eins zwei',
    type: ReplacementTypeEnum.verbConjugation,
    rule: null,
  );

  /// Seats a match on the controller the way a fetch would. `setSpanData` is
  /// the only public door into the match list; the private one is filled by the
  /// network path this test does not run.
  PangeaMatchState seat(SpanData data) {
    final state = PangeaMatchState(
      original: PangeaMatch(match: data, status: PangeaMatchStatusEnum.open),
      match: data,
      status: PangeaMatchStatusEnum.open,
    );
    igc.setSpanData(state, data);
    return state;
  }

  setUp(() {
    MatrixState.pangeaController = _FakePangeaController();
    igc = IgcController((_) {}, () {});
  });

  tearDown(() => igc.dispose());

  Future<void> pumpCard(WidgetTester tester) async {
    final manager = WritingAssistancePopupManager(
      choreographer: _FakeChoreographer(igcController: igc, room: _FakeRoom()),
      onFeedbackSubmitted: (_) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SpanCard(controller: manager, maxHeight: 400),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the card follows every switch, not just the first', (
    tester,
  ) async {
    final first = seat(span(choice: 'Eins', feedback: 'about eins', offset: 0));
    final second = seat(
      span(choice: 'Zwei', feedback: 'about zwei', offset: 5),
    );

    await pumpCard(tester);

    igc.setMatchToShow(first);
    await tester.pumpAndSettle();
    expect(find.text('Eins'), findsOneWidget);
    expect(find.text('about eins'), findsOneWidget);

    igc.setMatchToShow(second);
    await tester.pumpAndSettle();
    expect(find.text('Zwei'), findsOneWidget);

    // Both matches are `viewed` by now, so nothing more reaches
    // matchUpdateStream — this is the tap the learner reported as dead.
    expect(first.updatedMatch.status, PangeaMatchStatusEnum.viewed);
    igc.setMatchToShow(first);
    await tester.pumpAndSettle();

    expect(find.text('Eins'), findsOneWidget);
    expect(find.text('about eins'), findsOneWidget);
    expect(find.text('Zwei'), findsNothing);
  });

  // Negative control: the card is driven by the active match and nothing else,
  // so a controller that never names one shows no card rather than the first
  // match it happens to hold.
  testWidgets('no active match shows no card', (tester) async {
    seat(span(choice: 'Eins', feedback: 'about eins', offset: 0));

    await pumpCard(tester);

    expect(find.text('Eins'), findsNothing);
  });
}

class _FakePangeaController implements PangeaController {
  @override
  final UserController userController = _FakeUserController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserController implements UserController {
  @override
  final StreamController<Profile> settingsUpdateStream =
      StreamController<Profile>.broadcast();

  /// Listen First off, the fresh-profile default for this card.
  @override
  bool isToolEnabled(ToolSetting setting) => false;

  /// Non-null: the choices row reads it for the language it speaks in.
  @override
  String? get userL2Code => 'de';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The card reaches the choreographer for the match list and the room its
/// choice audio is counted against. It never runs writing assistance here, so
/// the rest is left to [noSuchMethod].
class _FakeChoreographer implements Choreographer {
  _FakeChoreographer({required this.igcController, required this.room});

  @override
  final IgcController igcController;

  @override
  final Room room;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRoom implements Room {
  @override
  String get id => '!span-card:test';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
