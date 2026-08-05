import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/editable_transcript.dart';
import 'package:fluffychat/routes/chat/recording_input_row.dart';
import 'package:fluffychat/routes/chat/recording_view_model.dart';

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

  Future<RecordingViewModelState> pump(
    WidgetTester tester,
    VoiceMessageSend onSend,
  ) async {
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
    return state;
  }

  testWidgets(
    'D7/D9: a FAILED onSend leaves the buffer EDITABLE (not terminal sent); a '
    'subsequent edit still sets isEdited/editDistance (provenance stays honest)',
    (tester) async {
      final state = await pump(tester, (
        _,
        _,
        _,
        _, {
        streamedTranscript,
      }) async {
        throw Exception('network down');
      });

      state.debugEnterEditable('ola mundo');
      await tester.pump();
      final buf = state.editableTranscriptForTest!;

      // Send fails.
      await state.sendEditedTranscript((
        _,
        _,
        _,
        _, {
        streamedTranscript,
      }) async {
        throw Exception('network down');
      });
      await tester.pump();

      // Buffer must NOT be terminal `sent` — it stays editable for retry.
      // Teeth: marking sent BEFORE onSend succeeds leaves this `sent` -> RED.
      expect(buf.state, isNot(EditableTranscriptState.sent));
      expect(state.isEditingTranscript, isTrue);

      // A subsequent edit correctly updates provenance (would be corrupt if the
      // buffer were stuck terminal `sent`).
      await tester.enterText(find.byType(TextField), 'hola mundo');
      await tester.pump();
      expect(buf.isEdited, isTrue);
      expect(state.streamingSendData!.editDistance, 1);

      state.cancel();
      await tester.pump();
    },
  );

  testWidgets('D7: a SUCCESSFUL onSend marks the buffer sent and resets the '
      'recorder', (tester) async {
    var sends = 0;
    final state = await pump(tester, (_, _, _, _, {streamedTranscript}) async {
      sends++;
    });

    state.debugEnterEditable('hola mundo');
    await tester.pump();
    final buf = state.editableTranscriptForTest!;

    await state.sendEditedTranscript((_, _, _, _, {streamedTranscript}) async {
      sends++;
    });
    await tester.pump();

    expect(sends, 1);
    // Success: terminal `sent` (teardown does not relabel a sent buffer).
    expect(buf.state, EditableTranscriptState.sent);
    // The recorder reset after a successful send.
    expect(state.isEditingTranscript, isFalse);
  });
}
