import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/message_content.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_message_toolbar_host.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// #8792's paywall audit found `pangea.call_transcript` referenced ONLY inside
/// `lib/routes/chat/calls`: it is a custom event type with no `body` key, so
/// the standard timeline/search/notification paths have nothing to read and
/// cannot show its words -- `transcript_view.dart` is the one surface that
/// does. This proves that claim EXECUTABLY rather than leaving it as a grep
/// result: a transcript event carrying real words, run through the SAME
/// general-purpose [MessageContent] widget every ordinary timeline message
/// renders through, must never put those words on screen.
///
/// [MessageContent]'s own `switch (event.type)` has no case for
/// `CallTranscriptContent.relType` (only `EventTypes.Message`/`Encrypted`/
/// `Sticker`, a poll start, and a call invite are handled), so it falls to the
/// `default:` branch -- a generic "X sent an unknown event" sentence built
/// from the sender's name and the event TYPE STRING alone, never from
/// `event.content`. This is exactly the kind of path the design doc allows a
/// "provably cannot receive transcript strings" claim for, and the second
/// assertion below pins that the default branch is what actually ran, not a
/// silently-empty render that would pass the first assertion for the wrong
/// reason.
void main() {
  group('pangea.call_transcript through the general timeline (#8792)', () {
    setUpAll(() async {
      // `MessageContent`'s sender-display-name path reads `BotName
      // .byEnvironment` -> `Environment.botName` -> `dotenv.env` for EVERY
      // sender (to decide whether they ARE the bot), so any render through it
      // throws `NotInitializedError` without this -- same bootstrap as
      // `transcript_view_test.dart` and `call_mini_tile_test.dart`.
      final tempDir = await Directory.systemTemp.createTemp(
        'call_transcript_guard',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (methodCall) async => tempDir.path,
          );
      await GetStorage.init('env_override');
      dotenv.testLoad(
        mergeWith: {
          'BOT_NAME': 'pangeabot',
          'SYNAPSE_URL': 'https://fakeServer.notExisting',
        },
      );
    });

    late Client client;
    late Room room;
    late Timeline timeline;

    setUp(() async {
      MatrixState.pangeaController = FakePangeaController();
      client = await getTestClient();
      // Quiesce the sync loop: its retry timers would trip the binding's
      // pending-timer invariant.
      client.backgroundSync = false;
      client.abortSync();
      room = Room(id: '!guard:fakeServer.notExisting', client: client);
      timeline = await room.getTimeline();
    });

    tearDown(() async {
      timeline.cancelSubscriptions();
      await client.dispose();
    });

    testWidgets(
      'the general MessageContent renderer never shows a transcript word',
      (tester) async {
        const marker = 'zzz-transcript-marker-word';
        final content = CallTranscriptContent(
          callKey: r'$call:fakeServer.notExisting',
          segments: const [TranscriptSegment(marker)],
          accounting: const HalfAccounting(
            chunksCaptured: 1,
            chunksTranscribed: 1,
            declared: true,
          ),
        );
        final event = Event(
          type: CallTranscriptContent.relType,
          eventId: r'$transcript:fakeServer.notExisting',
          senderId: '@peer:fakeServer.notExisting',
          originServerTs: DateTime.now(),
          content: content.toJson(),
          room: room,
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: MessageContent(
                event,
                textColor: Colors.black,
                linkColor: Colors.blue,
                borderRadius: BorderRadius.zero,
                timeline: timeline,
                selected: false,
                controller: FakeMessageToolbarHost(room),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Mutation: if any general-purpose surface read this event's
        // `segments` and rendered them, the marker word would be findable
        // here -> RED.
        expect(find.textContaining(marker), findsNothing);
        // Pins that the generic "unknown event" fallback is what actually
        // rendered -- see this file's own doc for why that matters.
        expect(
          find.textContaining(CallTranscriptContent.relType),
          findsOneWidget,
        );
      },
    );
  });
}
