import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/active_suggestion_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_feedback_dialog.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_feedback_repo.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_goal_completion.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrchestratorFeedbackPart', () {
    test('sends the wire values the endpoint accepts', () {
      // The server constrains `part` to exactly these two; a Dart enum name
      // (goalCompletion) would be a 422.
      expect(OrchestratorFeedbackPart.suggestion.wireValue, 'suggestion');
      expect(
        OrchestratorFeedbackPart.goalCompletion.wireValue,
        'goal_completion',
      );
    });
  });

  group('ActiveSuggestionModel carries the turn it came from', () {
    ActiveSuggestionModel model() => ActiveSuggestionModel(
      suggestion: OrchestratorRoleSuggestions(
        roleId: 'customer',
        suggestions: const [
          OrchestratorSuggestion(
            text: 'Buenas tardes',
            type: OrchestratorSuggestionType.best,
          ),
        ],
      ),
      basedOnEventId: r'$evt001',
      goalCompletion: const [
        OrchestratorRoleGoalCompletion(
          roleId: 'customer',
          goalIds: ['greet', 'ask_drinks'],
        ),
      ],
    );

    test('exposes the id the flag points at', () {
      expect(model().basedOnEventId, r'$evt001');
    });

    test('carries the turn\'s awards for the picker', () {
      // A goal flag must name one of these. Prose alone made the model
      // re-judge a different award than the reviewer meant.
      expect(model().goalCompletion.single.goalIds, ['greet', 'ask_drinks']);
    });

    test('copyWith keeps the awards too', () {
      final selected = model().copyWith(
        selectedChoice: model().suggestion.suggestions.first,
      );
      expect(selected.goalCompletion.single.goalIds, ['greet', 'ask_drinks']);
    });

    test('copyWith keeps it', () {
      // A tapped choice must not lose the pointer — the flag is most likely
      // pressed after interacting with the card.
      final selected = model().copyWith(
        selectedChoice: model().suggestion.suggestions.first,
      );
      expect(selected.basedOnEventId, r'$evt001');
    });
  });

  group('the flag dialog', () {
    const choreoApi = 'https://api.test.pangea.chat';

    setUpAll(() async {
      // `Environment.choreoApi` consults the persisted app-config override
      // before dotenv, and that storage wants a documents directory.
      final tempDir = await Directory.systemTemp.createTemp('orch_feedback');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (methodCall) async => tempDir.path,
          );
      await GetStorage.init('env_override');
      MatrixState.pangeaController = FakePangeaController(
        accessToken: 'syt_test_token',
      );
    });

    setUp(() => dotenv.testLoad(mergeWith: {'CHOREO_API': choreoApi}));

    testWidgets('a sent flag thanks the reviewer and closes the dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          // Mirrors the app: the workspace shell wraps its Scaffold in a
          // ScaffoldMessenger of its own, so the MaterialApp's root messenger
          // — the one a root-navigator dialog resolves to — owns no Scaffold
          // to present a snackbar in (workspace_shell.dart).
          home: ScaffoldMessenger(
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showOrchestratorFeedbackDialog(
                    context: context,
                    roomId: '!session:fakeServer.notExisting',
                    basedOnEventId: r'$evt001',
                    ownRoleId: 'customer',
                    goalCompletion: const [],
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await runWithClient(() async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'wrong tense');
        await tester.pump();
        await tester.tap(find.widgetWithText(TextButton, 'Send'));
        await tester.pumpAndSettle();
      }, () => MockClient((_) async => Response('{}', 200)));

      expect(tester.takeException(), isNull);
      expect(find.text('Flagged. Thanks!'), findsOneWidget);
      expect(find.text("What's wrong here?"), findsNothing);
    });
  });
}
