import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:async/async.dart' as async;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' hide Client;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_report_dialog.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_report_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #9044 — the team's report that a goal star was wrongly given or wrongly
/// withheld. The two halves that can break silently are the wire body (the
/// endpoint rejects evidence on an over-award and demands it on an under-award)
/// and the submit gate that keeps a reporter from reaching those rejections.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const choreoApi = 'https://api.test.pangea.chat';
  const roomId = '!session:fakeServer.notExisting';
  const senderId = '@test:fakeServer.notExisting';

  setUpAll(() async {
    // `Environment.choreoApi` consults the persisted app-config override before
    // dotenv, and that storage wants a documents directory.
    final tempDir = await Directory.systemTemp.createTemp('goal_report');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    // The evidence picker reuses the chat's visibility filter, which reads the
    // hide-redacted and hide-unknown settings.
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'syt_test_token',
    );
  });

  setUp(() => dotenv.testLoad(mergeWith: {'CHOREO_API': choreoApi}));

  const goal = ActivityRoleGoal(
    id: 'row-id-1',
    goalSlug: 'order_drink',
    description: 'Order a drink',
  );

  group('GoalReportDirection', () {
    test('sends the wire values the endpoint accepts', () {
      // The server constrains `direction` to exactly these two; a Dart enum
      // name (overAward) would be a 422.
      expect(GoalReportDirection.overAward.wireValue, 'over_award');
      expect(GoalReportDirection.underAward.wireValue, 'under_award');
    });
  });

  group('GoalReportRepo.submit', () {
    /// The body of the one request the repo made, with [response] served back.
    Future<(Map<String, dynamic>, async.Result<void>)> capture({
      required GoalReportDirection direction,
      String comment = 'the customer never ordered anything',
      String? evidenceEventId,
      int? evidenceOriginTs,
      Response Function()? response,
    }) async {
      Map<String, dynamic>? sent;
      final result = await runWithClient(
        () => GoalReportRepo.submit(
          roomId: roomId,
          roleId: 'customer',
          goalId: 'order_drink',
          direction: direction,
          comment: comment,
          evidenceEventId: evidenceEventId,
          evidenceOriginTs: evidenceOriginTs,
        ),
        () => MockClient((request) async {
          expect(
            request.url.toString(),
            '$choreoApi/choreo/orchestrate/goal_report',
          );
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return response?.call() ??
              Response(jsonEncode({'report_id': 'rep-1'}), 200);
        }),
      );
      return (sent!, result);
    }

    test('an over-award carries no evidence keys at all', () async {
      final (sent, result) = await capture(
        direction: GoalReportDirection.overAward,
      );

      expect(result.isValue, isTrue);
      expect(sent['room_id'], roomId);
      expect(sent['role_id'], 'customer');
      expect(sent['goal_id'], 'order_drink');
      expect(sent['direction'], 'over_award');
      // Not merely null: the endpoint rejects an over-award that names an
      // evidence message, and a null key is a named one.
      expect(sent.containsKey('evidence_event_id'), isFalse);
      expect(sent.containsKey('evidence_origin_ts'), isFalse);
    });

    test('an under-award carries the message it claims as evidence', () async {
      final (sent, result) = await capture(
        direction: GoalReportDirection.underAward,
        evidenceEventId: r'$evt001',
        evidenceOriginTs: 1758566400000,
      );

      expect(result.isValue, isTrue);
      expect(sent['direction'], 'under_award');
      expect(sent['evidence_event_id'], r'$evt001');
      // The timestamp travels with the id because the nominated message often
      // triggered no call of its own; the server resolves the nearest turn
      // after it.
      expect(sent['evidence_origin_ts'], 1758566400000);
    });

    test('the comment is trimmed before it is sent', () async {
      final (sent, _) = await capture(
        direction: GoalReportDirection.overAward,
        comment: '  it was the bot that ordered  ',
      );

      expect(sent['comment'], 'it was the bot that ordered');
    });

    test('a rejection comes back as an error carrying the detail', () async {
      final (_, result) = await capture(
        direction: GoalReportDirection.overAward,
        response: () => Response(
          jsonEncode({'detail': 'turn did not award order_drink to customer'}),
          422,
        ),
      );

      expect(result.isError, isTrue);
      final error = result.asError!.error;
      expect(PangeaHttpException.statusCodeOf(error), 422);
      // The reporter is shown this: it names which mismatch, which is what
      // tells them they picked the wrong star or the wrong message.
      expect(
        (error as PangeaHttpException).detail,
        'turn did not award order_drink to customer',
      );
    });
  });

  group('the report prompt', () {
    late Client client;
    late Room room;
    late Timeline timeline;

    setUp(() async {
      client = await getTestClient();
      room = Room(id: roomId, client: client);
      timeline = await room.getTimeline();
    });
    tearDown(() async {
      timeline.cancelSubscriptions();
      await client.dispose();
    });

    Event rawEvent(
      String eventId,
      Map<String, dynamic> content, {
      String sender = senderId,
      int minute = 0,
      Map<String, dynamic>? unsigned,
    }) => Event(
      type: EventTypes.Message,
      content: content,
      senderId: sender,
      eventId: eventId,
      originServerTs: DateTime.utc(2026, 9, 22, 12, minute),
      unsigned: unsigned,
      room: room,
    );

    Event message(String body, int seq) =>
        rawEvent('\$msg$seq', {'msgtype': 'm.text', 'body': body}, minute: seq);

    /// A voice message. Its body is what the SDK falls back to, which for a
    /// voice message says nothing the reporter recognises.
    Event voiceMessage(int seq, {String? transcript}) => rawEvent('\$msg$seq', {
      'msgtype': 'm.audio',
      'body': '\$msg$seq',
      if (transcript != null)
        'user_stt': {
          'results': [
            {
              'transcripts': [
                {
                  'confidence': 90,
                  'lang_code': 'es',
                  'transcript': transcript,
                  'words_per_hr': 100,
                  'stt_tokens': <Map<String, dynamic>>[],
                },
              ],
            },
          ],
        },
    }, minute: seq);

    Future<void> open(
      WidgetTester tester, {
      required GoalReportDirection direction,
      List<Event> timelineEvents = const [],
    }) async {
      timeline.events
        ..clear()
        ..addAll(timelineEvents);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          // Mirrors the app: the workspace shell wraps its Scaffold in a
          // ScaffoldMessenger of its own, so the Scaffolds a snackbar can
          // render in belong to THAT messenger, not the MaterialApp's root one
          // (workspace_shell.dart).
          home: ScaffoldMessenger(
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showGoalReportDialog(
                    context: context,
                    room: room,
                    roleId: 'customer',
                    goal: goal,
                    direction: direction,
                    timelineOverride: () async => timeline,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      // The localization delegates resolve asynchronously, so the first frame
      // carries no app at all.
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    /// Null when the prompt cannot be submitted.
    VoidCallback? sendAction(WidgetTester tester) => tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Send'))
        .onPressed;

    testWidgets('a filled star asks why it should not have been given', (
      tester,
    ) async {
      await open(tester, direction: GoalReportDirection.overAward);

      expect(
        find.text(
          'If you were not supposed to get this star, please explain why.',
        ),
        findsOneWidget,
      );
      // Which star, so the reporter is not guessing behind the dialog.
      expect(find.text('Order a drink'), findsOneWidget);
      // An over-award names no message, so there is nothing to pick.
      expect(find.byType(RadioListTile<String>), findsNothing);
    });

    testWidgets('an over-award needs only a comment', (tester) async {
      await open(tester, direction: GoalReportDirection.overAward);

      expect(sendAction(tester), isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      // Blank is what the server rejects, so whitespace must not pass either.
      expect(sendAction(tester), isNull);

      await tester.enterText(find.byType(TextField), 'the bot ordered, not me');
      await tester.pump();
      expect(sendAction(tester), isNotNull);
    });

    testWidgets('an under-award cannot be sent without a message', (
      tester,
    ) async {
      await open(
        tester,
        direction: GoalReportDirection.underAward,
        timelineEvents: [
          message('un café por favor', 1),
          message('gracias', 2),
        ],
      );

      expect(
        find.text('If you think you were supposed to get this star, why?'),
        findsOneWidget,
      );
      expect(find.text('un café por favor'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'I ordered in the first line',
      );
      await tester.pump();
      // A comment alone is not enough: the endpoint demands the evidence
      // message, and reaching that 422 is the thing this gate prevents.
      expect(sendAction(tester), isNull);

      await tester.tap(find.text('un café por favor'));
      await tester.pumpAndSettle();
      expect(sendAction(tester), isNotNull);
    });

    testWidgets('lists only the messages the chat shows as the reporter\'s', (
      tester,
    ) async {
      await open(
        tester,
        direction: GoalReportDirection.underAward,
        timelineEvents: [
          message('hola', 1),
          voiceMessage(2, transcript: 'quiero un café'),
          // #9267: playing another message aloud leaves an audio event under
          // the LISTENER's name carrying that message's words. The chat hides
          // it; the picker used to offer it as the listener's own voice
          // message.
          rawEvent(r'$readAloud', {
            'msgtype': 'm.audio',
            'body': r'audio_for_$bot1_es.mp3',
            'transcription': {'text': 'Qué día tan bonito'},
            'm.relates_to': {
              'rel_type': 'pangea.text_to_speech',
              'event_id': r'$bot1',
            },
          }),
          // An edit is its own event but not a second message.
          rawEvent(r'$edit', {
            'msgtype': 'm.text',
            'body': '* hola!',
            'm.new_content': {'msgtype': 'm.text', 'body': 'hola!'},
            'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$msg1'},
          }),
          rawEvent(r'$other', {
            'msgtype': 'm.text',
            'body': 'buenas',
          }, sender: '@bot:fakeServer.notExisting'),
          rawEvent(
            r'$gone',
            {},
            unsigned: {
              'redacted_because': {
                'type': EventTypes.Redaction,
                'sender': senderId,
                'event_id': r'$redaction',
                'content': <String, dynamic>{},
              },
            },
          ),
        ],
      );

      expect(find.byType(RadioListTile<String>), findsNWidgets(2));
      expect(find.text('hola'), findsOneWidget);
      expect(find.text('quiero un café'), findsOneWidget);
    });

    testWidgets('a voice message is listed by its stored transcript', (
      tester,
    ) async {
      await open(
        tester,
        direction: GoalReportDirection.underAward,
        timelineEvents: [
          voiceMessage(1, transcript: 'quiero un café'),
          voiceMessage(2),
        ],
      );

      // #9259: the transcript, never the body the SDK falls back to.
      expect(find.text('quiero un café'), findsOneWidget);
      expect(find.text(r'$msg1'), findsNothing);
      // Nothing stored and nothing requested: named as a voice message, told
      // apart from the others by its time.
      expect(find.text('Voice message'), findsOneWidget);
      expect(find.text(r'$msg2'), findsNothing);

      await tester.enterText(find.byType(TextField), 'I ordered out loud');
      await tester.tap(find.text('quiero un café'));
      await tester.pumpAndSettle();
      expect(sendAction(tester), isNotNull);
    });

    testWidgets('an edited message is sent as its latest edit', (tester) async {
      final original = message('un cafe', 1);
      Event edit(String eventId, String body, int minute) => rawEvent(eventId, {
        'msgtype': 'm.text',
        'body': '* $body',
        'm.new_content': {'msgtype': 'm.text', 'body': body},
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$msg1'},
      }, minute: minute);
      timeline.addAggregatedEvent(edit(r'$edit1', 'un café', 5));
      timeline.addAggregatedEvent(edit(r'$edit2', 'un café, por favor', 9));

      Map<String, dynamic>? sent;
      await runWithClient(
        () async {
          await open(
            tester,
            direction: GoalReportDirection.underAward,
            timelineEvents: [original],
          );
          // Listed by what the chat shows now, at the time it was first sent.
          await tester.tap(find.text('un café, por favor'));
          await tester.enterText(find.byType(TextField), 'I ordered politely');
          await tester.pump();
          await tester.tap(find.widgetWithText(TextButton, 'Send'));
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return Response('{"report_id": "rep-1"}', 200);
        }),
      );

      // #9267: the orchestrator's history carries an edited message under its
      // newest edit, so the original's id would match no turn.
      expect(sent?['evidence_event_id'], r'$edit2');
      expect(
        sent?['evidence_origin_ts'],
        DateTime.utc(2026, 9, 22, 12, 9).millisecondsSinceEpoch,
      );
    });

    testWidgets('a sent report thanks the reporter and closes the prompt', (
      tester,
    ) async {
      await runWithClient(
        () async {
          await open(tester, direction: GoalReportDirection.overAward);
          await tester.enterText(
            find.byType(TextField),
            'the bot ordered, not me',
          );
          await tester.pump();
          await tester.tap(find.widgetWithText(TextButton, 'Send'));
          await tester.pumpAndSettle();
        },
        () => MockClient((_) async => Response('{"report_id": "rep-1"}', 200)),
      );

      // The confirmation is shown by the messenger above the popped dialog, so
      // it must not be looked up through the dialog's own dead context.
      expect(tester.takeException(), isNull);
      expect(find.text('Reported. Thanks!'), findsOneWidget);
      expect(find.text('Order a drink'), findsNothing);
    });

    testWidgets('a long comment wraps instead of widening the prompt', (
      tester,
    ) async {
      // A screen wide enough that filling it cannot pass for a normal width.
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await open(tester, direction: GoalReportDirection.overAward);
      final field = find.byType(TextField);
      final openWidth = tester.getSize(field).width;

      await tester.enterText(field, 'la cuenta ' * 40);
      await tester.pump();

      // Wrapped at the dialog's width, not stretched toward the screen's.
      expect(tester.getSize(field).width, openWidth);
      expect(openWidth, lessThan(800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an under-award with nothing said says so', (tester) async {
      await open(tester, direction: GoalReportDirection.underAward);

      expect(
        find.text(
          "You haven't sent a message in this session yet, so there's nothing "
          'to point at.',
        ),
        findsOneWidget,
      );
      expect(sendAction(tester), isNull);
    });
  });
}
