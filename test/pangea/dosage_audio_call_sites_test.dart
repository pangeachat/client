import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where each listening category may be named, enforced mechanically.
///
/// The spec's central rule is that **the category is a constant at each emit
/// site, never a runtime discriminator** (D-V2-1): the shared playback
/// components serve several surfaces at once and cannot tell the categories
/// apart, so only the caller may name one. That rule is invisible in a diff —
/// adding `DosageListeningCategory.peer` inside `audio_player.dart` compiles,
/// analyzes clean, passes every behavioural test, and silently books the
/// practice card's paid audio as a peer voice message.
///
/// So it is pinned here instead of trusted to review. A hand-maintained
/// convention drifts; a mechanical invariant fails.
void main() {
  String read(String path) {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$path moved — update this invariant with it',
    );
    return file.readAsStringSync();
  }

  /// Every `lib/` file naming [needle], excluding the feature's own directory
  /// (which necessarily names all of them: the enum, its coverage mapping and
  /// the timeline predicate live there).
  List<String> callersOf(String needle) =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('lib/features/dosage/'))
          .where((f) => f.readAsStringSync().contains(needle))
          .map((f) => f.path)
          .toList()
        ..sort();

  group('one category, one emit site', () {
    test('peer listening is decided ONLY where the sender is real', () {
      // The predicate is called from the timeline call site alone. It is sound
      // there because the sender is a real Matrix sender; the practice widgets
      // pass the learner's own mxid for audio the learner did not send, so the
      // same test would be wrong there.
      expect(callersOf('DosageListeningCategory.forTimelineAudio'), [
        'lib/routes/chat/message_content.dart',
      ]);
    });

    test('automatic read-aloud is named ONLY by its controller', () {
      expect(callersOf('DosageListeningCategory.autoRead'), [
        'lib/routes/chat/events/text_to_speech/message_read_aloud_controller.dart',
      ]);
    });

    test('tapped read-aloud is named ONLY by the toolbar button', () {
      expect(callersOf('DosageListeningCategory.tapRead'), [
        'lib/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart',
      ]);
    });
  });

  group('shared components name no category', () {
    test('the shared audio player only RECEIVES one', () {
      final source = read('lib/routes/chat/audio_player.dart');
      for (final category in ['peer', 'autoRead', 'tapRead']) {
        expect(
          source.contains('DosageListeningCategory.$category'),
          isFalse,
          reason:
              'audio_player serves the timeline, the practice card and the '
              'analytics practice widget; naming a category here attributes '
              'all three to one',
        );
      }
      expect(
        source.contains('DosageListeningCategory? listeningCategory'),
        isTrue,
      );
    });

    test('the TTS controller names none either', () {
      final source = read(
        'lib/routes/chat/events/text_to_speech/tts_controller.dart',
      );
      expect(source.contains('DosageListeningCategory'), isFalse);
      // It reports WHEN playback starts and leaves what that means to the
      // caller, which is what lets one entry point serve read-aloud, word taps
      // and choice taps without any of them borrowing another's category.
      expect(source.contains('onPlaybackStarted'), isTrue);
    });
  });

  group('both shared-player surfaces watch ownership', () {
    test('each closes its measurement from the owner notifier', () {
      // A player-state subscription alone is not enough. A surface that takes
      // the one global player stops and DISPOSES the player the other surface
      // is subscribed to, and a disposed player closes its state stream — so
      // the transition that would have closed the measurement may never arrive.
      // The meter would keep running and, at dispose, book the other surface's
      // playback under this one's category.
      //
      // Ownership changes through the notifier whether or not a state event
      // follows, so both surfaces must watch it. Pinned mechanically because
      // the two implementations are separate and only one of them had it.
      for (final path in [
        'lib/routes/chat/audio_player.dart',
        'lib/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart',
      ]) {
        final source = read(path);
        expect(
          source.contains(
            'voiceMessageEventId.addListener(_onListeningOwnershipChange)',
          ),
          isTrue,
          reason: '$path must close its measurement when it loses the player',
        );
        expect(
          source.contains(
            'voiceMessageEventId.removeListener(_onListeningOwnershipChange)',
          ),
          isTrue,
          reason: '$path must drop that listener on dispose',
        );
      }
    });
  });

  group('the practice surfaces stay out of scope', () {
    test('neither practice call site passes a category', () {
      // Both are message-scoped and one is paid, so both COULD be counted. They
      // are excluded because they are drill surfaces: including them would put
      // practice behaviour into a conversation metric.
      for (final path in [
        'lib/routes/chat/toolbar/message_practice/message_audio_card.dart',
        'lib/routes/analytics/construct_analytics/practice/analytics_practice_content_widget.dart',
      ]) {
        expect(
          read(path).contains('listeningCategory'),
          isFalse,
          reason: '$path is a practice surface and must emit nothing',
        );
      }
    });
  });

  group('speaking emits from the voice send', () {
    test('onVoiceMessageSend records a dosage envelope', () {
      final source = read('lib/routes/chat/chat.dart');
      final start = source.indexOf('Future<void> onVoiceMessageSend(');
      expect(start, greaterThan(-1));
      // A line unique to this method, after the send has resolved.
      final end = source.indexOf(
        'readAloudController.voiceMode = true;',
        start,
      );
      expect(end, greaterThan(start));

      expect(
        source
            .substring(start, end)
            .contains('DosageMessageSignals.emitForSentMessage'),
        isTrue,
        reason:
            'without this envelope the server can only learn a voice message '
            'exists from a pvm construct use, which is missing when the '
            'tokens are unsavable or background enrichment was interrupted',
      );
    });

    test('no duration is sent with it — the server reads that from Matrix', () {
      final source = read('lib/features/dosage/dosage_message_event.dart');
      expect(source.contains('duration'), isFalse);
    });
  });
}
