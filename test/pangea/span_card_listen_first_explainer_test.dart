import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Profile;

import 'package:fluffychat/features/instructions/instruction_settings.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
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

/// #9124 — a dismissed Listen First explainer must leave no gap.
///
/// Dismissing the explainer records it on the learner's profile, but the card
/// only rebuilds when that write comes back through sync. Until then the
/// collapsed explainer stayed in the card's spaced column, so the card kept
/// the spacing below the choices — and the next Listen First toggle rebuilt it
/// away, changing the card's height.
///
/// See writing-assistance.instructions.md § Hearing a choice.
void main() {
  late IgcController igc;
  late _FakeUserController user;

  setUp(() {
    user = _FakeUserController();
    MatrixState.pangeaController = _FakePangeaController(user);
    igc = IgcController((_) {}, () {});
  });

  tearDown(() => igc.dispose());

  Future<void> pumpCard(WidgetTester tester) async {
    final data = SpanData(
      message: null,
      shortMessage: null,
      choices: [
        SpanChoice(
          value: 'Eins',
          type: SpanChoiceTypeEnum.suggestion,
          feedback: 'about eins',
        ),
      ],
      offset: 0,
      length: 4,
      fullText: 'eins zwei',
      type: ReplacementTypeEnum.verbConjugation,
      rule: null,
    );
    final match = PangeaMatchState(
      original: PangeaMatch(match: data, status: PangeaMatchStatusEnum.open),
      match: data,
      status: PangeaMatchStatusEnum.open,
    );
    igc.setSpanData(match, data);

    final manager = WritingAssistancePopupManager(
      choreographer: _FakeChoreographer(igcController: igc, room: _FakeRoom()),
      onFeedbackSubmitted: (_) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              // Wide enough that the header keeps Listen First inline.
              width: 800,
              child: SpanCard(controller: manager, maxHeight: 600),
            ),
          ),
        ),
      ),
    );
    igc.setMatchToShow(match);
    await tester.pumpAndSettle();
  }

  double cardHeight(WidgetTester tester) =>
      tester.getSize(find.byType(SpanCard)).height;

  Future<void> toggleListenFirst(WidgetTester tester) async {
    await tester.tap(
      find.byIcon(
        user.listenFirst ? Icons.headphones : Icons.headphones_outlined,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dismissing the explainer leaves no gap before sync lands', (
    tester,
  ) async {
    user.listenFirst = true;
    await pumpCard(tester);
    final l10n = L10n.of(tester.element(find.byType(SpanCard)));
    expect(find.text(l10n.listenFirstDescription), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pumpAndSettle();
    expect(InstructionsEnum.listenFirst.isToggledOff, isTrue);
    final dismissed = cardHeight(tester);

    await toggleListenFirst(tester);
    expect(user.listenFirst, isFalse);
    expect(cardHeight(tester), dismissed);

    await toggleListenFirst(tester);
    expect(user.listenFirst, isTrue);
    expect(cardHeight(tester), dismissed);
  });

  // Control: the explainer does take space while it is showing, so the
  // equalities above measure its absence rather than a card that never grew.
  testWidgets('the explainer grows the card while it is showing', (
    tester,
  ) async {
    await pumpCard(tester);
    final withoutListenFirst = cardHeight(tester);

    await toggleListenFirst(tester);
    expect(cardHeight(tester), greaterThan(withoutListenFirst));
  });
}

class _FakePangeaController implements PangeaController {
  _FakePangeaController(this.userController);

  @override
  final UserController userController;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Holds the profile in memory and applies writes to it, but never echoes them
/// on [settingsUpdateStream] — the state the card is in between a write and the
/// sync that returns it.
class _FakeUserController implements UserController {
  bool listenFirst = false;

  @override
  final StreamController<Profile> settingsUpdateStream =
      StreamController<Profile>.broadcast();

  @override
  final Completer<void> initCompleter = Completer<void>()..complete();

  @override
  Profile profile = Profile(
    userSettings: UserSettings(),
    instructionSettings: InstructionSettings(instructions: {}),
  );

  @override
  bool isToolEnabled(ToolSetting setting) => switch (setting) {
    ToolSetting.listenFirst => listenFirst,
    ToolSetting.audioChoices => true,
    _ => false,
  };

  @override
  Future<void> setListenFirst(bool value) async => listenFirst = value;

  @override
  Future<void> updateProfile(
    Profile Function(Profile) update, {
    waitForDataInSync = false,
  }) async => profile = update(profile);

  @override
  String? get userL2Code => 'de';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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
