import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/transcript_edited_flag.dart';
import '../get_test_client.dart';

/// D9 flag coverage on the REAL audio-message mount decision. The production
/// audio case at message_content.dart is a single call to
/// [AudioMessageEditedFlag.wrap] — the mount decision (stack the flag above the
/// player IFF `user_stt.edited == true`, else return the player untouched) is
/// factored into that seam so it is unit-testable without rendering the
/// MatrixState-singleton-gated AudioPlayerWidget subtree. The `wrap` group below
/// drives that exact seam through a REAL [PangeaMessageEvent] and the REAL
/// [PangeaMessageEvent.isTranscriptEdited] reader, so removing/inverting the
/// wrap (or a regression in the reader or provenance-key contract) turns this
/// suite RED. The first group additionally pins the flag widget's own render.
///
/// Residual limit: message_content.dart's ONE-LINE call to the seam is not
/// itself render-tested (the player subtree cannot mount under `flutter test`);
/// that call-site wiring is review-gated. Everything the call delegates to IS
/// pinned here.
void main() {
  late Client client;
  late Room room;
  late Timeline timeline;

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!voice:fakeServer.notExisting', client: client);
    timeline = await room.getTimeline();
  });

  tearDown(() async {
    timeline.cancelSubscriptions();
    await client.dispose();
  });

  PangeaMessageEvent audio(Map<String, dynamic>? userStt) => PangeaMessageEvent(
    event: Event(
      type: EventTypes.Message,
      eventId: r'$audioflag:fakeServer.notExisting',
      senderId: client.userID!,
      originServerTs: DateTime.now(),
      content: {
        'msgtype': 'm.audio',
        'body': 'recording.wav',
        'user_stt': ?userStt,
      },
      room: room,
    ),
    timeline: timeline,
    ownMessage: true,
  );

  Widget host(PangeaMessageEvent event) => MaterialApp(
    home: Scaffold(body: AudioMessageEditedFlag(pangeaMessageEvent: event)),
  );

  testWidgets(
    'edited voice message (user_stt.edited == true) -> the edit pencil is '
    'in the audio-message tree',
    (tester) async {
      await tester.pumpWidget(host(audio({SttProvenanceKeys.edited: true})));
      final iconFinder = find.byIcon(Icons.edit_outlined);
      expect(iconFinder, findsOneWidget);
      expect(
        tester.widget<Icon>(iconFinder).color,
        Theme.of(tester.element(iconFinder)).colorScheme.onSurfaceVariant,
      );
    },
  );

  testWidgets('verbatim voice message (edited == false) -> NO pencil', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(audio({SttProvenanceKeys.edited: false, 'results': <dynamic>[]})),
    );
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('pre-provenance voice message (no edited key) -> NO pencil', (
    tester,
  ) async {
    await tester.pumpWidget(host(audio({'results': <dynamic>[]})));
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  group('AudioMessageEditedFlag.wrap (the production mount decision)', () {
    // A sentinel audio body so we can assert it is returned untouched vs wrapped.
    const audioBody = SizedBox(key: Key('audio-body'), width: 42, height: 60);

    testWidgets(
      'edited == true -> preserves player dimensions and overlays the marker',
      (tester) async {
        final wrapped = AudioMessageEditedFlag.wrap(
          audioBody,
          audio({SttProvenanceKeys.edited: true}),
        );
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: wrapped)));

        // The player body is preserved and remains the primary interaction.
        expect(find.byKey(const Key('audio-body')), findsOneWidget);
        expect(find.byType(AudioMessageEditedFlag), findsOneWidget);
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const Key('audio-edited-marker-stack'))),
          const Size(42, 60),
        );
      },
    );

    testWidgets(
      'edited == true -> the tile textColor is applied to the pencil',
      (tester) async {
        // The mount passes the bubble's textColor so the marker reads on the
        // (light) voice bubble. Teeth: dropping `color: color` in wrap()/build()
        // falls the pencil back to onSurfaceVariant here -> RED.
        const tileText = Color(0xFF0A0A2A);
        final wrapped = AudioMessageEditedFlag.wrap(
          audioBody,
          audio({SttProvenanceKeys.edited: true}),
          color: tileText,
        );
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: wrapped)));
        expect(
          tester.widget<Icon>(find.byIcon(Icons.edit_outlined)).color,
          tileText,
        );
      },
    );

    testWidgets(
      'edited != true -> returns the player body UNCHANGED (no flag, identical '
      'widget instance)',
      (tester) async {
        final verbatim = AudioMessageEditedFlag.wrap(
          audioBody,
          audio({SttProvenanceKeys.edited: false, 'results': <dynamic>[]}),
        );
        // Teeth: the seam must return the SAME widget, not a wrapper. If the
        // wrap always stacked (or inverted the predicate), this identity fails.
        expect(identical(verbatim, audioBody), isTrue);

        await tester.pumpWidget(MaterialApp(home: Scaffold(body: verbatim)));
        expect(find.byType(AudioMessageEditedFlag), findsNothing);
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
      },
    );

    testWidgets('null message (non-audio / legacy) -> body UNCHANGED', (
      tester,
    ) async {
      final result = AudioMessageEditedFlag.wrap(audioBody, null);
      expect(identical(result, audioBody), isTrue);
    });
  });

  testWidgets(
    'timeline marker never mounts transcript text or expands the tile',
    (tester) async {
      final edited = audio({
        SttProvenanceKeys.edited: true,
        SttProvenanceKeys.originalAsr: 'ola mundo',
        'results': [
          {
            'alternatives': [
              {'transcript': 'hola mundo'},
            ],
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AudioMessageEditedFlag.wrap(
                const SizedBox(key: Key('audio-body'), width: 280, height: 60),
                edited,
              ),
            ),
          ),
        ),
      );

      expect(find.text('hola'), findsNothing);
      expect(find.text('ola'), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('audio-edited-marker-stack'))),
        const Size(280, 60),
      );
      final marker = tester.getRect(find.byType(AudioMessageEditedFlag));
      final body = tester.getRect(find.byKey(const Key('audio-body')));
      expect(marker.left, greaterThan(body.left + body.width / 2));
      expect(marker.bottom, lessThanOrEqualTo(body.bottom));
    },
  );

  testWidgets('edited marker is passive and cannot steal audio interaction', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioMessageEditedFlag(
            pangeaMessageEvent: audio({SttProvenanceKeys.edited: true}),
          ),
        ),
      ),
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.edit_outlined),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });
}
