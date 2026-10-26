import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/journey_checklist/journey_checklist_extension.dart';
import 'package:fluffychat/features/journey_checklist/journey_checklist_writes.dart';
import 'package:fluffychat/features/journey_checklist/journey_step_enum.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const path =
      '/client/v3/user/%40test%3AfakeServer.notExisting/account_data/${PangeaEventTypes.journeyChecklist}';
  final at = DateTime.fromMillisecondsSinceEpoch(1000);

  late Client client;
  late FakeMatrixApi api;

  List<Map<String, Object?>> writes() =>
      (FakeMatrixApi.calledEndpoints[path] ?? [])
          .map((body) => jsonDecode(body as String) as Map<String, Object?>)
          .toList();

  setUp(() async {
    JourneyChecklistWrites.reset();
    client = await getTestClient();
    api = FakeMatrixApi.currentApi!;
    // Lets an account-data write come back through sync, as on a server.
    FakeMatrixApi.client = client;
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() async {
    await client.dispose();
  });

  group('recordJourneyStep', () {
    test('saves the step with the time it happened', () async {
      await client.recordJourneyStep(JourneyStep.completePractice, at: at);

      expect(writes().single['steps'], {'complete_practice': 1000});
    });

    test('a later occurrence of a recorded step writes nothing', () async {
      await client.recordJourneyStep(JourneyStep.completePractice, at: at);
      await client.recordJourneyStep(JourneyStep.completePractice);

      expect(writes(), hasLength(1));
    });

    test('two steps recorded before the first syncs back both land', () async {
      // A server that accepts writes without syncing them back, so the
      // second write is built before the first is in account data.
      api.api['PUT']![path] = (_) => <String, Object?>{};

      await Future.wait([
        client.recordJourneyStep(JourneyStep.closeTrialPage, at: at),
        client.recordJourneyStep(JourneyStep.acceptTranslation, at: at),
      ]);

      expect(writes().last['steps'], {
        'close_trial_page': 1000,
        'accept_translation': 1000,
      });
    });

    test('keeps the ask history already on the account', () async {
      final prompts = {
        'allow_notifications': {'dismissCount': 1, 'lastDismissedAt': 500},
      };
      await client.setAccountData(
        client.userID!,
        PangeaEventTypes.journeyChecklist,
        {'prompts': prompts},
      );
      FakeMatrixApi.calledEndpoints.clear();

      await client.recordJourneyStep(JourneyStep.viewSubscriptionPage, at: at);

      expect(writes().single['prompts'], prompts);
    });

    test('a failed save is retried on the next occurrence', () async {
      api.api['PUT']![path] = (_) => {
        'errcode': 'M_FORBIDDEN',
        'error': 'Not allowed',
      };
      await client.recordJourneyStep(JourneyStep.completePractice, at: at);

      api.api['PUT']!.remove(path);
      await client.recordJourneyStep(JourneyStep.completePractice, at: at);

      expect(writes(), hasLength(2));
      expect(
        client.journeyChecklist.hasStep(JourneyStep.completePractice),
        isTrue,
      );
    });
  });
}
