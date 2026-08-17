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
  /// call site can read `DosageListeningCategory\n    .wordAudio`. A plain
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

    test('word audio is named ONLY where a WORD was played', () {
      // All four word surfaces, now that a roomless one can emit: the word-card
      // tap on a token in a message, the vocab list tile, the activity vocab
      // chip, and the pronunciation button. Adding a fifth file here means a new
      // surface started counting, which changes what a teacher-visible total
      // contains.
      expect(callersOf('DosageListeningCategory.wordAudio'), [
        'lib/routes/analytics/construct_analytics/vocab_analytics_list_view.dart',
        'lib/routes/chat/activity_sessions/activity_vocab_widget.dart',
        'lib/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart',
        'lib/routes/chat/toolbar/message_selection_overlay.dart',
      ]);
    });

    test('practice audio is named ONLY by drill surfaces', () {
      expect(callersOf('DosageListeningCategory.practiceAudio'), [
        'lib/pangea/common/widgets/choice_array.dart',
        'lib/routes/analytics/construct_analytics/practice/analytics_practice_ui_controller.dart',
        'lib/routes/chat/toolbar/message_practice/practice_controller.dart',
        'lib/routes/chat/toolbar/message_practice/practice_match_item.dart',
      ]);
    });

    test('a word tap and a drill tap cannot swap categories', () {
      // The two categories are the split the app already makes to decide gating
      // — `TtsUseCase.words` against `TtsUseCase.choices` — so a site filed
      // under the wrong one is invisible in a diff and produces two precise
      // counters that both mean something else. Pinned per file, for all eight.
      const expected = {
        'lib/routes/analytics/construct_analytics/vocab_analytics_list_view.dart':
            'wordAudio',
        'lib/routes/chat/activity_sessions/activity_vocab_widget.dart':
            'wordAudio',
        'lib/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart':
            'wordAudio',
        'lib/routes/chat/toolbar/message_selection_overlay.dart': 'wordAudio',
        'lib/pangea/common/widgets/choice_array.dart': 'practiceAudio',
        'lib/routes/analytics/construct_analytics/practice/analytics_practice_ui_controller.dart':
            'practiceAudio',
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

  group('every read-aloud path measures, and says which room', () {
    // `tryToSpeak` takes a REQUIRED probe, so a new read-aloud path cannot
    // compile without naming a category and a room. That closes the omission
    // but not the drift: a site can change category, change room, or be added,
    // in a diff nobody reads closely. All three are pinned here.

    /// Every `lib/` file that builds a listening probe, with its site count.
    Map<String, int> probeSites() {
      final pattern = RegExp(r'DosageTtsListeningProbe\(');
      return {
        for (final path in callersOf('DosageTtsListeningProbe('))
          path: pattern.allMatches(read(path)).length,
      };
    }

    test('ten read-aloud sites emit, plus the two message reads', () {
      // The TEN (pangeachat/client#8408, review) are every `TtsUseCase.words`
      // and `TtsUseCase.choices` playback, across eight files; the message
      // read-aloud controller's two are categories 2 and 4 and came first.
      // Pinned per file and per SITE, so a site added to a file already on the
      // list still shows up — a file count alone would have missed the three
      // that share the analytics practice controller.
      //
      // Twelve calls, and no exemptions: a number moving here means a surface
      // started or stopped counting, which changes what a teacher-visible total
      // contains. That is meant to be a visible diff, not a silent one.
      final calls = {
        for (final path in callersOf('TtsController.tryToSpeak('))
          path: RegExp(
            r'TtsController\.tryToSpeak\(',
          ).allMatches(read(path)).length,
      };
      expect(calls, {
        // The six drill sites.
        'lib/pangea/common/widgets/choice_array.dart': 1,
        'lib/routes/analytics/construct_analytics/practice/analytics_practice_ui_controller.dart':
            3,
        'lib/routes/chat/toolbar/message_practice/practice_controller.dart': 1,
        'lib/routes/chat/toolbar/message_practice/practice_match_item.dart': 1,
        // The four word sites.
        'lib/routes/analytics/construct_analytics/vocab_analytics_list_view.dart':
            1,
        'lib/routes/chat/activity_sessions/activity_vocab_widget.dart': 1,
        'lib/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart':
            1,
        'lib/routes/chat/toolbar/message_selection_overlay.dart': 1,
        // Categories 2 and 4, which came first.
        'lib/routes/chat/events/text_to_speech/message_read_aloud_controller.dart':
            2,
      });
      expect(calls.values.fold<int>(0, (a, b) => a + b), 12);

      // And every one of those files builds a probe. `tryToSpeak` takes a
      // required one, so this cannot currently be false — which is the point:
      // it fails the day somebody reintroduces an optional or exempt form and
      // a site quietly stops emitting while still compiling.
      expect(probeSites().keys.toSet(), calls.keys.toSet());
    });

    test('the exemption vocabulary is gone, not merely unused', () {
      // With every site measured, `DosageListeningMeasurement` and
      // `DosageListeningExemption` have no callers. Leaving the types behind
      // would leave the next roomless surface an off-ramp that reads as
      // sanctioned — the undercount they were invented to make visible, back
      // again with a name that says it is fine.
      expect(callersOf('DosageListeningMeasurement'), isEmpty);
      expect(callersOf('DosageListeningExemption'), isEmpty);
      expect(
        File(
          'lib/features/dosage/dosage_listening_measurement.dart',
        ).existsSync(),
        isFalse,
      );
    });

    test('a roomless site passes null, never an invented room', () {
      // The room is the ONE argument that differs between two sites of the same
      // category, and the failure mode is silent both ways: a fabricated room
      // files a learner's listening under a course they were never in, and a
      // null where a room existed drops it out of the course bucket while the
      // whole-language total still looks right. Neither shows up as a broken
      // playback, so both are pinned as expressions.
      //
      // Read from the probe's own argument list, not the whole file: two of
      // these files pass a `roomId` to a WIDGET as well, and a file-wide probe
      // would happily match that instead.
      Set<String> probeRooms(String path) {
        final source = read(path);
        final rooms = <String>{};
        for (final match in RegExp(
          r'DosageTtsListeningProbe\(',
        ).allMatches(source)) {
          final tail = source.substring(match.end);
          // The probe's four arguments are written in this order everywhere;
          // `userId` bounds the slice so a later `roomId:` cannot leak in.
          final end = tail.indexOf('userId:');
          expect(
            end,
            greaterThan(-1),
            reason: '$path: a probe with no identity',
          );
          final room = RegExp(
            r'roomId:\s*([^,]+),',
          ).firstMatch(tail.substring(0, end));
          expect(room, isNotNull, reason: '$path: a probe that names no room');
          rooms.add(room!.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim());
        }
        return rooms;
      }

      const expected = {
        // Roomed: the message, the exercise's message, the caller's room.
        'lib/routes/chat/toolbar/message_selection_overlay.dart': {
          'pangeaMessageEvent.room.id',
        },
        'lib/routes/chat/toolbar/message_practice/practice_controller.dart': {
          'pangeaMessageEvent.room.id',
        },
        'lib/routes/chat/toolbar/message_practice/practice_match_item.dart': {
          'widget.controller.pangeaMessageEvent.room.id',
        },
        'lib/routes/chat/events/text_to_speech/message_read_aloud_controller.dart':
            {'room.id'},
        'lib/pangea/common/widgets/choice_array.dart': {'roomId'},
        // Permanently roomless: a cross-room aggregate has no one room, and
        // choosing one of the rooms a word came from would be a guess.
        'lib/routes/analytics/construct_analytics/vocab_analytics_list_view.dart':
            {'null'},
        // Sometimes roomed: the widget's own room, null where the surface that
        // built it has none. NOT a target id, an event id or a cache key — each
        // of those is a non-room string in scope at these sites.
        'lib/routes/chat/activity_sessions/activity_vocab_widget.dart': {
          'widget.roomId',
        },
        'lib/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart':
            {'widget.roomId'},
        // Forwards its own parameter; the call sites are pinned below.
        'lib/routes/analytics/construct_analytics/practice/analytics_practice_ui_controller.dart':
            {'roomId'},
      };

      expected.forEach((path, rooms) {
        expect(probeRooms(path), rooms, reason: '$path names these rooms');
      });

      // Where a probe reads a NAME rather than an expression, pin where that
      // name gets its value — otherwise the assertion above says only that some
      // variable was passed along.
      expect(
        RegExp(r'_listeningProbe\(([^)]*)\)')
            .allMatches(
              read(
                'lib/routes/analytics/construct_analytics/practice/analytics_practice_ui_controller.dart',
              ),
            )
            .map((m) => m.group(1)!.trim())
            .toSet(),
        // The audio exercise is built from a real message and carries its room;
        // the meaning exercises are assembled from construct history and have
        // none. `String? roomId` is the builder's own signature.
        {'String? roomId', 'exercise.roomId', 'null'},
      );

      // The two widgets that span roomed and roomless hosts. Their room is a
      // REQUIRED argument, so a new host has to answer the question rather than
      // inherit a default — and what each host answers is pinned here, because
      // "the room went missing" looks identical to a working feature: the audio
      // plays, the minutes count, they just stop reaching a course.
      const hosts = {
        // The in-chat activity summary has a session room; the start page runs
        // before one exists.
        'lib/routes/chat/activity_sessions/activity_summary_widget.dart':
            'roomId: room?.id,',
        'lib/routes/chat/activity_sessions/activity_sessions_start_view.dart':
            'roomId: null,',
        // The word card is opened from a message when there is one; the
        // analytics practice hosts have none.
        'lib/routes/chat/toolbar/word_card/word_zoom_widget.dart':
            'roomId: event?.room.id,',
        'lib/routes/analytics/construct_analytics/practice/ongoing_analytics_practice_session_view.dart':
            'roomId: null,',
      };
      hosts.forEach((path, expression) {
        expect(
          read(path).contains(expression),
          isTrue,
          reason: '$path must hand down `$expression`',
        );
      });
    });

    test('no probe is handed a hardcoded room', () {
      // A string literal here would put every learner's listening in one room —
      // a per-room table the serving side buckets and authorizes on. It is the
      // one shortcut that makes the numbers look plausible while being wrong
      // for everybody.
      for (final path in probeSites().keys) {
        expect(
          RegExp(r"""roomId:\s*['"]""").hasMatch(read(path)),
          isFalse,
          reason: '$path must never name a room literally',
        );
      }
    });

    test('the shared choices widget cannot be given a default room', () {
      // `ChoicesArray` is generic, shared, and has no room of its own — only
      // its caller knows one. A room a caller MAY omit is a room a caller will
      // omit, and the emit would then have to invent one or go dark, which is
      // how this gap opened in the first place. Required is what makes a third
      // caller a compile error rather than a silent undercount, and a default
      // slipped in later would look like a tidy convenience.
      expect(
        read(
          'lib/pangea/common/widgets/choice_array.dart',
        ).contains('required this.roomId'),
        isTrue,
        reason: 'ChoicesArray must take its room, never assume one',
      );

      // And NON-nullable, unlike the widgets that span roomed and roomless
      // hosts. Both of this one's callers have a real room, so null here would
      // not be a roomless surface reporting itself — it would be a caller that
      // lost its room, silently downgraded to "no course".
      expect(
        read(
          'lib/pangea/common/widgets/choice_array.dart',
        ).contains('final String roomId;'),
        isTrue,
        reason: 'ChoicesArray has no roomless caller to be nullable for',
      );

      // And both callers hand it a REAL room rather than a literal. A hardcoded
      // string here would put every learner's choice audio in one room.
      const callers = {
        'lib/routes/chat/choreographer/igc/span_card.dart':
            '_choreographer.room.id',
        'lib/routes/chat/choreographer/activity_orchestrator/suggestion_card.dart':
            'widget.controller.room.id',
      };
      callers.forEach((path, expression) {
        expect(
          read(path).contains('roomId: $expression'),
          isTrue,
          reason: '$path must pass its own room to ChoicesArray',
        );
      });
    });
  });

  group('the shared-player practice surfaces are still dark', () {
    test('neither practice call site passes a category', () {
      // These two are the AudioPlayerWidget half of the same gap: both are
      // message-scoped and one is paid, so both COULD be counted, and the
      // decision is now that they SHOULD be. Neither the vocabulary nor the
      // room blocks them any more — what keeps them dark is that they come
      // through a different entry point, wired differently, and are their own
      // change (#8411). This assertion holds until that one lands.
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
