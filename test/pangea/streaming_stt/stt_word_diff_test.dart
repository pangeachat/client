import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/stt_word_diff.dart';

void main() {
  // Reconstruction is the core invariant: concatenating run texts == edited.
  String recon(List<SttDiffRun> runs) => runs.map((r) => r.text).join();
  List<String> changed(List<SttDiffRun> runs) =>
      runs.where((r) => r.changed).map((r) => r.text).toList();

  group('sttWordDiff', () {
    test('identical -> a single unchanged run (revert-proven)', () {
      final runs = sttWordDiff('hola mundo', 'hola mundo');
      expect(runs, hasLength(1));
      expect(runs.single.changed, isFalse);
      expect(runs.single.text, 'hola mundo');
    });

    test('single-word substitution at the front', () {
      final runs = sttWordDiff('ola mundo', 'hola mundo');
      expect(recon(runs), 'hola mundo');
      expect(changed(runs), ['hola']);
    });

    test('multiple changes in one edit', () {
      final runs = sttWordDiff('the quick brown fox', 'the slow brown wolf');
      expect(recon(runs), 'the slow brown wolf');
      expect(changed(runs), ['slow', 'wolf']);
    });

    test('insertion -> only the inserted word is changed', () {
      final runs = sttWordDiff('hola mundo', 'hola bonito mundo');
      expect(recon(runs), 'hola bonito mundo');
      expect(changed(runs), ['bonito']);
    });

    test('deletion -> no changed run in the edited text', () {
      final runs = sttWordDiff('hola bonito mundo', 'hola mundo');
      expect(recon(runs), 'hola mundo');
      expect(changed(runs), isEmpty);
    });

    test(
      'multi-word INSERTION -> ONE continuous changed run (whitespace continuity)',
      () {
        final runs = sttWordDiff('hola', 'hola muy bonito');
        expect(recon(runs), 'hola muy bonito');
        // The inserted phrase is a SINGLE run "muy bonito", not two changed words
        // split by an unchanged green space (which would break a fill highlight).
        expect(changed(runs), ['muy bonito']);
      },
    );

    test('multi-word REPLACEMENT -> ONE continuous changed run', () {
      final runs = sttWordDiff('a x y b', 'a p q b');
      expect(recon(runs), 'a p q b');
      expect(changed(runs), ['p q']);
    });

    test('grapheme-safe: an accented word is one changed run', () {
      final runs = sttWordDiff('café', 'cafe');
      expect(recon(runs), 'cafe');
      expect(changed(runs), ['cafe']);
    });

    test('grapheme-safe: an emoji swap is one changed run', () {
      final runs = sttWordDiff('me gusta 👍', 'me gusta 👎');
      expect(recon(runs), 'me gusta 👎');
      expect(changed(runs), ['👎']);
    });

    test('empty original -> the whole edited text is one changed run', () {
      final runs = sttWordDiff('', 'hola');
      expect(runs, hasLength(1));
      expect(runs.single.changed, isTrue);
      expect(runs.single.text, 'hola');
    });

    test('empty edited -> no runs (reconstructs to empty)', () {
      final runs = sttWordDiff('hola', '');
      expect(recon(runs), '');
      expect(runs, isEmpty);
    });
  });

  group('sttWordChanges', () {
    test('pairs a replacement with only its original spoken word', () {
      expect(sttWordChanges('ola mundo', 'hola mundo'), [
        (current: 'hola', original: 'ola', changed: true),
        (current: 'mundo', original: null, changed: false),
      ]);
    });

    test('marks an insertion without inventing an original word', () {
      expect(sttWordChanges('hola mundo', 'hola bonito mundo'), [
        (current: 'hola', original: null, changed: false),
        (current: 'bonito', original: null, changed: true),
        (current: 'mundo', original: null, changed: false),
      ]);
    });

    test('keeps a deletion local instead of repeating the full transcript', () {
      expect(sttWordChanges('hola bonito mundo', 'hola mundo'), [
        (current: 'hola', original: null, changed: false),
        (current: null, original: 'bonito', changed: true),
        (current: 'mundo', original: null, changed: false),
      ]);
    });

    test('pairs multiple substitutions in order', () {
      expect(sttWordChanges('the quick brown fox', 'the slow brown wolf'), [
        (current: 'the', original: null, changed: false),
        (current: 'slow', original: 'quick', changed: true),
        (current: 'brown', original: null, changed: false),
        (current: 'wolf', original: 'fox', changed: true),
      ]);
    });
  });
}
