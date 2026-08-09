import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/editable_transcript.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';

SttPartial _final(String text, {List<SttWord> words = const <SttWord>[]}) =>
    SttPartial(
      transcript: text,
      words: words,
      isFinal: true,
      speechFinal: false,
    );

SttPartial _partial(String text) => SttPartial(
  transcript: text,
  words: const [],
  isFinal: false,
  speechFinal: false,
);

void main() {
  test('constructor pre-fills settled final as SYSTEM text; editableClean, '
      'not edited, distance 0', () {
    final buf = EditableTranscript(originalAsrText: 'hola mundo');
    addTearDown(buf.dispose);

    expect(buf.state, EditableTranscriptState.editableClean);
    expect(buf.currentText, 'hola mundo');
    expect(buf.originalAsrText, 'hola mundo');
    expect(buf.isEdited, isFalse);
    expect(buf.editDistance, 0);
  });

  test('a real USER keystroke moves editableClean -> editableDirty; isEdited '
      'true; distance reflects the edit', () {
    final buf = EditableTranscript(originalAsrText: 'ola mundo');
    addTearDown(buf.dispose);

    // Simulate a user keystroke by writing through the controller directly (NOT
    // setSystemText).
    buf.controller.text = 'hola mundo';

    expect(buf.state, EditableTranscriptState.editableDirty);
    expect(buf.isEdited, isTrue);
    expect(buf.editDistance, 1); // inserted 'h'
    // Teeth: if the controller listener ignored user edits, state stays clean -> RED.
  });

  test('SYSTEM pre-fill does NOT set dirty (a re-prefill of the same/other '
      'text keeps editableClean)', () {
    final buf = EditableTranscript(originalAsrText: 'hola');
    addTearDown(buf.dispose);

    buf.controller.setSystemText('hola mundo');

    expect(buf.state, EditableTranscriptState.editableClean);
    expect(buf.isEdited, isFalse);
  });

  test('late FINAL arriving in editableClean (no edit yet) DOES update and '
      're-settles the verbatim base', () {
    final buf = EditableTranscript(originalAsrText: 'hola');
    addTearDown(buf.dispose);

    final applied = buf.applyStreamingUpdate(_final('hola mundo'));

    expect(applied, isTrue);
    expect(buf.currentText, 'hola mundo');
    expect(buf.originalAsrText, 'hola mundo'); // re-settled base
    expect(buf.state, EditableTranscriptState.editableClean);
    expect(buf.isEdited, isFalse);
    expect(buf.editDistance, 0);
  });

  test('a NON-final PARTIAL arriving in editableClean (no edit yet) is '
      'DISCARDED — never drifts currentText from the settled base', () {
    final buf = EditableTranscript(originalAsrText: 'hola mundo');
    addTearDown(buf.dispose);

    final applied = buf.applyStreamingUpdate(_partial('hola mun'));

    // Teeth: if editableClean accepted the non-final partial (the pre-fix
    // behaviour), currentText would become 'hola mun' while originalAsrText
    // stayed 'hola mundo' — a corrupt record: isEdited false yet distance > 0.
    expect(applied, isFalse);
    expect(buf.currentText, 'hola mundo'); // base untouched
    expect(buf.originalAsrText, 'hola mundo');
    expect(buf.isEdited, isFalse);
    expect(buf.editDistance, 0); // the invariant the bug violated
  });

  test('a late FINAL re-settle in editableClean updates the word timings '
      'ALONGSIDE the base (D9 alignment)', () {
    const oldWords = [
      SttWord(word: 'hola', start: 0, end: 0.4, confidence: 0.9),
    ];
    const newWords = [
      SttWord(word: 'hola', start: 0, end: 0.4, confidence: 0.9),
      SttWord(word: 'mundo', start: 0.4, end: 0.9, confidence: 0.9),
    ];
    final buf = EditableTranscript(originalAsrText: 'hola', words: oldWords);
    addTearDown(buf.dispose);

    final applied = buf.applyStreamingUpdate(
      _final('hola mundo', words: newWords),
    );

    expect(applied, isTrue);
    expect(buf.originalAsrText, 'hola mundo');
    // Teeth: pre-fix the re-settle updated originalAsrText but left `words` at
    // oldWords — timings misaligned against the new base. They must move together.
    expect(buf.words, same(newWords));
    expect(buf.words.length, 2);
  });

  test('LATE-FINAL-VS-EDIT: a FINAL arriving AFTER the first user keystroke is '
      'DISCARDED — the edited text stays', () {
    final buf = EditableTranscript(originalAsrText: 'ola mundo');
    addTearDown(buf.dispose);

    // User edits first -> dirty.
    buf.controller.text = 'hola mundo edited';
    expect(buf.state, EditableTranscriptState.editableDirty);

    // A late streaming final now arrives. It MUST NOT clobber the user's edit.
    final applied = buf.applyStreamingUpdate(
      _final('completely different asr'),
    );

    expect(applied, isFalse);
    expect(buf.currentText, 'hola mundo edited');
    expect(buf.state, EditableTranscriptState.editableDirty);
    // Teeth: allowing streaming updates in editableDirty overwrites the edit -> RED.
  });

  test(
    'a PARTIAL arriving after the first user keystroke is also DISCARDED',
    () {
      final buf = EditableTranscript(originalAsrText: 'ola');
      addTearDown(buf.dispose);
      buf.controller.text = 'hola edited';

      final applied = buf.applyStreamingUpdate(_partial('stale partial'));

      expect(applied, isFalse);
      expect(buf.currentText, 'hola edited');
    },
  );

  test('streaming updates in sent / cancelled are DISCARDED', () {
    final sentBuf = EditableTranscript(originalAsrText: 'hola');
    addTearDown(sentBuf.dispose);
    sentBuf.markSent();
    expect(sentBuf.applyStreamingUpdate(_final('x')), isFalse);
    expect(sentBuf.currentText, 'hola');

    final cancelledBuf = EditableTranscript(originalAsrText: 'hola');
    addTearDown(cancelledBuf.dispose);
    cancelledBuf.markCancelled();
    expect(cancelledBuf.applyStreamingUpdate(_final('y')), isFalse);
    expect(cancelledBuf.currentText, 'hola');
  });

  test('buildSendData: verbatim buffer -> isEdited false, distance 0, verbatim '
      'text == originalAsr, words + service carried', () {
    const words = [SttWord(word: 'hola', start: 0, end: 0.5, confidence: 0.9)];
    final buf = EditableTranscript(
      originalAsrText: 'hola mundo',
      words: words,
      service: 'deepgram',
    );
    addTearDown(buf.dispose);

    final data = buf.buildSendData();
    expect(data.text, 'hola mundo');
    expect(data.originalAsrText, 'hola mundo');
    expect(data.isEdited, isFalse);
    expect(data.editDistance, 0);
    expect(data.words, same(words));
    expect(data.service, 'deepgram');
  });

  test('buildSendData: edited buffer -> isEdited true, distance > 0, sent text '
      'differs from originalAsr; isEdited survives markSent', () {
    final buf = EditableTranscript(originalAsrText: 'ola mundo');
    addTearDown(buf.dispose);
    buf.controller.text = 'hola mundo';
    buf.markSent();

    final data = buf.buildSendData();
    expect(data.isEdited, isTrue);
    expect(data.text, 'hola mundo');
    expect(data.originalAsrText, 'ola mundo');
    expect(data.editDistance, 1);
    expect(buf.state, EditableTranscriptState.sent);
    expect(buf.isEdited, isTrue); // edited-then-sent is still flagged edited
  });

  test('edited then REVERTED to the exact original -> NOT flagged edited '
      '(the orange-flag "always shows" bug): a keystroke happened but the net '
      'text is unchanged, so edited=false / edit_distance=0', () {
    final buf = EditableTranscript(originalAsrText: 'hola mundo');
    addTearDown(buf.dispose);

    // A real keystroke dirties the buffer...
    buf.controller.text = 'hola mund';
    expect(buf.state, EditableTranscriptState.editableDirty);
    // ...then the learner reverts to EXACTLY the original.
    buf.controller.text = 'hola mundo';

    // Teeth: pre-fix isEdited == _reachedDirty -> `true` here (a keystroke ever
    // happened) even though the sent text equals the ASR. Must be false.
    expect(buf.editDistance, 0);
    expect(buf.isEdited, isFalse);
    final data = buf.buildSendData();
    expect(data.isEdited, isFalse);
    expect(data.editDistance, 0);
  });

  group('translation-cache invalidation (D7 guard)', () {
    test('fires ONCE on the first user edit; NOT on a system pre-fill', () {
      var invalidations = 0;
      final buf = EditableTranscript(
        originalAsrText: 'ola',
        onInvalidateTranslationCache: () => invalidations++,
      );
      addTearDown(buf.dispose);

      // System pre-fills must NOT invalidate.
      buf.controller.setSystemText('ola mundo');
      buf.applyStreamingUpdate(_final('ola mundo dos'));
      expect(invalidations, 0);

      // First user edit invalidates exactly once.
      buf.controller.text = 'hola mundo dos';
      expect(invalidations, 1);

      // Further user edits stay dirty but do not re-fire.
      buf.controller.text = 'hola mundo dos!';
      expect(invalidations, 1);
    });

    test('clears the buffer cached translation entry on first edit; retains it '
        'across a system pre-fill', () {
      final buf = EditableTranscript(originalAsrText: 'ola');
      addTearDown(buf.dispose);
      buf.cachedTranslation = 'hi world';

      // Survives a system pre-fill.
      buf.controller.setSystemText('ola mundo');
      expect(buf.cachedTranslation, 'hi world');

      // Dropped on the first user edit.
      buf.controller.text = 'hola mundo';
      expect(buf.cachedTranslation, isNull);
    });
  });

  test('settle re-aligns words with the settled base: omitting words CLEARS '
      'stale timings rather than keeping them misaligned (D9)', () {
    const oldWords = [
      SttWord(word: 'hola', start: 0, end: 0.4, confidence: 0.9),
    ];
    final buf = EditableTranscript.fromRecording();
    addTearDown(buf.dispose);

    // A final with words settles the base+timings during recording...
    buf.applyStreamingUpdate(_final('hola', words: oldWords));
    // ...then a settle with a DIFFERENT base text and NO words.
    buf.settle('hola mundo');

    expect(buf.originalAsrText, 'hola mundo');
    // Teeth: pre-fix `if (words != null) _words = words` kept oldWords, aligned
    // to 'hola' not 'hola mundo' — a stale D9 misalignment. It must clear.
    expect(buf.words, isEmpty);
  });

  test('buildSendData THROWS before settle (recording/finalizing) — never a '
      'corrupt pre-settle D9 snapshot; valid once settled', () {
    final buf = EditableTranscript.fromRecording();
    addTearDown(buf.dispose);

    buf.applyStreamingUpdate(_partial('hola')); // currentText diverges, base ''
    // Teeth: pre-guard this returned isEdited=false with editDistance>0.
    expect(buf.buildSendData, throwsStateError);

    buf.beginFinalizing();
    expect(buf.buildSendData, throwsStateError);

    buf.settle('hola mundo');
    expect(buf.buildSendData().originalAsrText, 'hola mundo');
    expect(buf.buildSendData().isEdited, isFalse);
  });

  group('full lifecycle from recording (the complete D7 machine)', () {
    test('applyStreamingUpdate applies in recording and finalizing; settle -> '
        'editableClean captures the base', () {
      final buf = EditableTranscript.fromRecording();
      addTearDown(buf.dispose);
      expect(buf.state, EditableTranscriptState.recording);

      expect(buf.applyStreamingUpdate(_partial('ho')), isTrue);
      expect(buf.currentText, 'ho');

      buf.beginFinalizing();
      expect(buf.state, EditableTranscriptState.finalizing);
      expect(buf.applyStreamingUpdate(_partial('hola')), isTrue);

      buf.settle('hola mundo');
      expect(buf.state, EditableTranscriptState.editableClean);
      expect(buf.originalAsrText, 'hola mundo');
      expect(buf.currentText, 'hola mundo');
      expect(buf.isEdited, isFalse);
    });
  });
}
