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

  /// A `Type.member` reference that survives the formatter.
  ///
  /// `dart format` breaks a long expression at the dot, so a deeply indented
  /// call site can read `DosageListeningExemption\n    .awaitingRoom`. A plain
  /// substring probe reports that file as naming NOTHING — which is the silent
  /// pass an invariant test exists to prevent, and it cost one debugging round
  /// here before it cost one in review.
  RegExp memberRef(String type, [String member = r'\w+']) =>
      RegExp('$type\\s*\\.\\s*($member)');

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

  /// [callersOf] for a reference the formatter may have wrapped.
  List<String> callersMatching(RegExp pattern) =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('lib/features/dosage/'))
          .where((f) => pattern.hasMatch(f.readAsStringSync()))
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

    test('toolbar-open read-aloud is named ONLY by its controller', () {
      expect(callersOf('DosageListeningCategory.toolbarRead'), [
        'lib/routes/chat/events/text_to_speech/message_read_aloud_controller.dart',
      ]);
    });

    test('word audio is named ONLY where a WORD was tapped', () {
      // One site, and it is the word-card tap on a token in a message. The
      // other word surfaces — the vocab list tile, the activity vocab chip, the
      // pronunciation button — are the same category and are still exempt for
      // want of a room, so this list grows when the room does, not before.
      expect(callersOf('DosageListeningCategory.wordAudio'), [
        'lib/routes/chat/toolbar/message_selection_overlay.dart',
      ]);
    });

    test('practice audio is named ONLY by drill surfaces', () {
      expect(callersOf('DosageListeningCategory.practiceAudio'), [
        'lib/pangea/common/widgets/choice_array.dart',
        'lib/routes/chat/toolbar/message_practice/practice_controller.dart',
        'lib/routes/chat/toolbar/message_practice/practice_match_item.dart',
      ]);
    });

    test('a word tap and a drill tap cannot swap categories', () {
      // The two new categories are the split the app already makes to decide
      // gating — `TtsUseCase.words` against `TtsUseCase.choices` — so a site
      // filed under the wrong one is invisible in a diff and produces two
      // precise counters that both mean something else. Pinned per site.
      const expected = {
        'lib/routes/chat/toolbar/message_selection_overlay.dart': 'wordAudio',
        'lib/pangea/common/widgets/choice_array.dart': 'practiceAudio',
        'lib/routes/chat/toolbar/message_practice/practice_controller.dart':
            'practiceAudio',
        'lib/routes/chat/toolbar/message_practice/practice_match_item.dart':
            'practiceAudio',
      };

      expected.forEach((path, category) {
        // Set equality on the members actually named, not a substring probe:
        // `wordAudio` and `practiceAudio` are both suffixed `Audio`, and a
        // probe for one that matched inside the other is exactly the silent
        // pass this idiom exists to prevent.
        expect(
          memberRef(
            'DosageListeningCategory',
          ).allMatches(read(path)).map((m) => m.group(1)).toSet(),
          {category},
          reason: '$path is $category listening and nothing else',
        );
      });
    });
  });

  group('the two read-aloud categories cannot swap', () {
    // Categories 2 and 4 share a file, a probe and an entry point, and differ
    // ONLY in the constant each method passes. That is the one thing a
    // whole-file check cannot see, so it is sliced per method here. Getting it
    // wrong would book every toolbar open as unprompted listening — a counter
    // whose entire meaning is "nobody asked".
    const controller =
        'lib/routes/chat/events/text_to_speech/message_read_aloud_controller.dart';

    String methodBody(String source, String signature, String nextSymbol) {
      final start = source.indexOf(signature);
      expect(start, greaterThan(-1), reason: '$signature moved');
      final end = source.indexOf(nextSymbol, start);
      expect(end, greaterThan(start), reason: '$nextSymbol moved');
      return source.substring(start, end);
    }

    test('the toolbar-open read names category 4 and nothing else', () {
      final body = methodBody(
        read(controller),
        'Future<void> readSelectedMessage(',
        'bool _isInTargetLanguage(',
      );
      expect(body.contains('DosageListeningCategory.toolbarRead'), isTrue);
      for (final other in ['autoRead', 'tapRead', 'peer']) {
        expect(
          body.contains('DosageListeningCategory.$other'),
          isFalse,
          reason: 'the toolbar-open read is category 4, never $other',
        );
      }
    });

    test('the automatic read names category 2 and nothing else', () {
      final body = methodBody(
        read(controller),
        'Future<void> _speak(',
        'DosageTtsListeningProbe _listeningProbe(',
      );
      expect(body.contains('DosageListeningCategory.autoRead'), isTrue);
      for (final other in ['toolbarRead', 'tapRead', 'peer']) {
        expect(
          body.contains('DosageListeningCategory.$other'),
          isFalse,
          reason: 'an arriving message is category 2, never $other',
        );
      }
    });

    test('the speaker button never names the toolbar-open category', () {
      expect(
        read(
          'lib/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart',
        ).contains('DosageListeningCategory.toolbarRead'),
        isFalse,
        reason:
            'the speaker button is a deliberate second listen on the paid '
            'route; folding it into the read-on-open counter would give that '
            'counter two meanings',
      );
    });
  });

  group('shared components name no category', () {
    test('the shared audio player only RECEIVES one', () {
      final source = read('lib/routes/chat/audio_player.dart');
      // `practiceAudio` is on this list deliberately: the practice card is one
      // of the three surfaces this player serves, so it is the category most
      // likely to look correct here and attribute all three to one.
      for (final category in [
        'peer',
        'autoRead',
        'tapRead',
        'toolbarRead',
        'wordAudio',
        'practiceAudio',
      ]) {
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

  group('every read-aloud path says what it measures', () {
    // `tryToSpeak` takes a REQUIRED measurement, so a new read-aloud path
    // cannot compile without naming either a category or an exemption. That
    // closes the omission but not the drift: an exempt site can be flipped to
    // measured, or a new measured site added, in a diff nobody reads closely.
    // Both lists are pinned here so either move is a failing test.

    test('five files measure listening through tryToSpeak', () {
      // Four of these were exempt until the category vocabulary grew. Adding a
      // sixth file here means a new surface started counting, which is a change
      // to what a teacher-visible total contains — it is meant to be a visible
      // diff, not a silent one.
      expect(
        callersMatching(memberRef('DosageListeningMeasurement', 'measured')),
        [
          'lib/pangea/common/widgets/choice_array.dart',
          'lib/routes/chat/events/text_to_speech/message_read_aloud_controller.dart',
          'lib/routes/chat/toolbar/message_practice/practice_controller.dart',
          'lib/routes/chat/toolbar/message_practice/practice_match_item.dart',
          'lib/routes/chat/toolbar/message_selection_overlay.dart',
        ],
      );
    });

    test('six sites across four files are exempt, each with its reason', () {
      // What is left of the ten (pangeachat/client#8408, review) once
      // `word_audio` and `practice_audio` landed. Every one of these is
      // listening and none is counted, so the served total is still short by
      // whatever they play — but the blocker is no longer the vocabulary. It is
      // the room: `room_id` is `min_length=1` on the wire and `NOT NULL` on
      // `dosage_audio_playback`, and, more to the point, `?bucket=course`
      // filters playbacks on the room while coverage carries no room conjunct,
      // so a null-room row would leave the student marked covered while their
      // rows are filtered out — a real 0 served for a learner who did listen.
      const expected = {
        'lib/routes/analytics/construct_analytics/practice/analytics_practice_ui_controller.dart':
            'awaitingRoom',
        'lib/routes/analytics/construct_analytics/vocab_analytics_list_view.dart':
            'awaitingRoom',
        'lib/routes/chat/activity_sessions/activity_vocab_widget.dart':
            'awaitingRoom',
        'lib/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart':
            'awaitingRoom',
      };

      final notMeasured = memberRef(
        'DosageListeningMeasurement',
        'notMeasured',
      );
      expect(callersMatching(notMeasured), expected.keys.toList()..sort());

      // Six CALL SITES, not six files: `analytics_practice_ui_controller`
      // carries three and the rest one each. Asserted rather than implied by the
      // file list, so a site added to a file already on it still shows up.
      final exemptSites = expected.keys
          .map((path) => notMeasured.allMatches(read(path)).length)
          .fold<int>(0, (a, b) => a + b);
      expect(exemptSites, 6);

      expected.forEach((path, reason) {
        // Read the members actually named, rather than probing for one at a
        // time: a substring probe silently passes when one member's name is a
        // prefix of another's, which is exactly how the first draft of this test
        // reported a file as claiming both reasons.
        final named = memberRef(
          'DosageListeningExemption',
        ).allMatches(read(path)).map((m) => m.group(1)).toSet();
        // One member, and it names the room. A file that reintroduced a
        // category-shaped reason would be claiming a blocker that no longer
        // exists, and would send the follow-up work to the wrong repo.
        expect(named, {reason}, reason: '$path is blocked on $reason alone');
      });
    });

    test('no exempt site names a category', () {
      // An exemption plus a category is a contradiction that would read, to the
      // next person, as a wired site — and would go on reading that way for as
      // long as nobody checked whether a probe was actually built.
      for (final path in callersMatching(
        memberRef('DosageListeningMeasurement', 'notMeasured'),
      )) {
        expect(
          memberRef('DosageListeningCategory').hasMatch(read(path)),
          isFalse,
          reason: '$path is exempt and must name no category',
        );
      }
    });
  });

  group('the shared-player practice surfaces are still dark', () {
    test('neither practice call site passes a category', () {
      // These two are the AudioPlayerWidget half of the same gap: both are
      // message-scoped and one is paid, so both COULD be counted, and the
      // decision is now that they SHOULD be. `practice_audio` describes them,
      // so what keeps them dark is no longer the vocabulary — it is that they
      // come through a different entry point, wired differently, and are their
      // own change (#8411). This assertion holds until that one lands.
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
