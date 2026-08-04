import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/editable_transcript.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streamed_stt_embed.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';
import 'package:fluffychat/routes/chat/degradation_banner.dart';
import 'package:fluffychat/routes/chat/recording_input_row.dart';
import 'package:fluffychat/routes/chat/recording_view_model.dart';

/// No-op wakelock so cancel()/_reset() (WakelockPlus.disable()) does not hit a
/// real platform channel.
class _FakeWakelock extends WakelockPlusPlatformInterface
    with MockPlatformInterfaceMixin {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    WakelockPlusPlatformInterface.instance = _FakeWakelock();
  });

  testWidgets(
    'D7: after stop the editable TextField REPLACES the read-only live line, '
    'pre-filled with the settled final (editableClean, not edited)',
    (tester) async {
      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: RecordingViewModel(
              builder: (context, s) {
                state = s;
                return RecordingInputRow(
                  state: s,
                  onSend: (_, _, _, _, {streamedTranscript}) async {},
                );
              },
            ),
          ),
        ),
      );
      await tester
          .pumpAndSettle(); // L10n delegates load async (no TextField yet)

      // Not editing yet: no editable field.
      expect(state.isEditingTranscript, isFalse);
      expect(find.byType(TextField), findsNothing);

      // Enter the editable state directly with a settled final (seam avoids the
      // real mic-stop / WAV synthesis / drain timing).
      state.debugEnterEditable('hola mundo');
      await tester.pump();

      expect(state.isEditingTranscript, isTrue);
      // The editable TextField is now present, pre-filled with the settled final.
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(state.editableController!.text, 'hola mundo');
      expect(
        state.editableTranscriptStateForTest,
        EditableTranscriptState.editableClean,
      );
      expect(state.streamingSendData!.isEdited, isFalse);

      state.cancel();
      await tester.pump();
    },
  );

  testWidgets(
    'D10 empty-stream guard: a settled EMPTY transcript routes to BATCH '
    '(no editable buffer, degraded-to-batch banner) instead of an empty base',
    (tester) async {
      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: RecordingViewModel(
              builder: (context, s) {
                state = s;
                return RecordingInputRow(
                  state: s,
                  onSend: (_, _, _, _, {streamedTranscript}) async {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The provider connected + streamed but produced nothing usable (e.g. Soniox
      // returns empty on ~1/10 German clips). Whitespace-only == empty after trim.
      state.debugEnterEditable('   ');
      await tester.pump();

      // We do NOT hand the user an empty editable base...
      expect(state.isEditingTranscript, isFalse);
      expect(find.byType(TextField), findsNothing);
      // ...it degrades to batch (server transcribes the retained WAV) and says so.
      expect(state.degradationBanner, DegradationBannerKind.degradedToBatch);

      state.cancel();
      await tester.pump();
    },
  );

  testWidgets('D7: a user keystroke in the editable field moves the buffer to '
      'editableDirty and marks the send-data edited', (tester) async {
    late RecordingViewModelState state;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: RecordingViewModel(
            builder: (context, s) {
              state = s;
              return RecordingInputRow(
                state: s,
                onSend: (_, _, _, _, {streamedTranscript}) async {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    state.debugEnterEditable('ola mundo');
    await tester.pump();

    // The learner corrects the transcript.
    await tester.enterText(find.byType(TextField), 'hola mundo');
    await tester.pump();

    expect(
      state.editableTranscriptStateForTest,
      EditableTranscriptState.editableDirty,
    );
    final data = state.streamingSendData!;
    expect(data.isEdited, isTrue);
    expect(data.text, 'hola mundo');
    expect(data.originalAsrText, 'ola mundo');
    expect(data.editDistance, 1);

    state.cancel();
    await tester.pump();

    // Teardown drops the editable buffer.
    expect(state.isEditingTranscript, isFalse);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'D8/D9 SEND BOUNDARY: the edited transcript + provenance reach onSend, and '
    'build a user_stt embed carrying the edited text with the flag lit',
    (tester) async {
      StreamingSttSendData? captured;
      var sendCalls = 0;
      Future<void> onSend(
        String path,
        int duration,
        List<int> waveform,
        String? fileName, {
        StreamingSttSendData? streamedTranscript,
      }) async {
        sendCalls++;
        captured = streamedTranscript;
      }

      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: RecordingViewModel(
              builder: (context, s) {
                state = s;
                return RecordingInputRow(state: s, onSend: onSend);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Settle a final, then the learner corrects it.
      state.debugEnterEditable(
        'ola mundo',
        result: StreamingSttResult(
          wavPath: '/tmp/voice.wav',
          transcript: 'ola mundo',
          duration: const Duration(seconds: 1),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'hola mundo');
      await tester.pump();

      // Send through the real VM path.
      await state.sendEditedTranscript(onSend);
      await tester.pump();

      // Teeth: pre-fix sendEditedTranscript called onSend WITHOUT
      // streamedTranscript, so `captured` was null and the embed below never got
      // built -> the edit + flag were lost at the send boundary.
      expect(sendCalls, 1);
      expect(captured, isNotNull);
      expect(captured!.isEdited, isTrue);
      expect(captured!.text, 'hola mundo'); // the EDIT, not the raw ASR
      expect(captured!.originalAsrText, 'ola mundo');
      expect(captured!.editDistance, 1);

      // The provenance builds a user_stt embed whose transcript is the edited
      // text (bot replies to it) and whose flag reader lights up.
      final embed = streamedUserSttEmbed(captured!, langCode: 'en');
      final parsed = SpeechToTextResponseModel.fromJson(embed);
      expect(parsed.transcript.text, 'hola mundo');
      expect(parsed.transcript.sttTokens, isEmpty); // skip_tokenize base
      expect(parsed.transcript.wordTimings, isNull); // omitted when edited (D8)
      expect(sttTranscriptEditedFromUserStt(embed), isTrue);
    },
  );
}
