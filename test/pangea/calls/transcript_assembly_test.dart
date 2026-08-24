import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';

const alice = '@alice:example.com';
const bob = '@bob:example.com';

TranscriptCandidate _candidate(
  String sender, {
  List<String> texts = const ['hola'],
  int ts = 1000,
  HalfAccounting accounting = const HalfAccounting(
    chunksCaptured: 2,
    chunksTranscribed: 2,
    declared: true,
  ),
}) => TranscriptCandidate(
  senderId: sender,
  originServerTs: ts,
  segments: [for (final text in texts) TranscriptSegment(text)],
  accounting: accounting,
);

TranscriptHalf _halfFor(CallTranscript transcript, String sender) =>
    transcript.halves.firstWhere((half) => half.senderId == sender);

void main() {
  group('assembleTranscript', () {
    test('both speakers present when both wrote', () {
      final transcript = assembleTranscript(
        candidates: [_candidate(alice), _candidate(bob)],
        expectedSenders: [alice, bob],
      );

      expect(transcript.halves.map((h) => h.senderId), [alice, bob]);
      expect(
        transcript.halves.map((h) => h.state),
        everyElement(HalfState.present),
      );
    });

    test('a speaker who wrote nothing is reported absent, not omitted', () {
      // Omitting them would read as "there was no second person".
      final transcript = assembleTranscript(
        candidates: [_candidate(alice)],
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, bob).state, HalfState.absent);
      expect(_halfFor(transcript, bob).segments, isEmpty);
    });

    test('a capped read reports incomplete, never absent', () {
      // The load-bearing distinction: absence may only be concluded from an
      // exhausted read. A cap that reported absence would say someone was
      // silent when we simply stopped looking.
      final transcript = assembleTranscript(
        candidates: [_candidate(alice)],
        expectedSenders: [alice, bob],
        exhausted: false,
      );

      expect(_halfFor(transcript, bob).state, HalfState.incomplete);
      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
      expect(transcript.readerStoppedEarly, isTrue);
    });

    test('a writer admitting gaps is incomplete even when exhausted', () {
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            accounting: const HalfAccounting(
              chunksCaptured: 5,
              chunksTranscribed: 3,
              declared: true,
            ),
          ),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
    });

    test('an abandoned drain makes a half incomplete', () {
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            accounting: const HalfAccounting(
              chunksCaptured: 2,
              chunksTranscribed: 2,
              drainComplete: false,
              declared: true,
            ),
          ),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
    });

    test('truncation makes a half incomplete', () {
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            accounting: const HalfAccounting(
              chunksCaptured: 2,
              chunksTranscribed: 2,
              truncated: true,
              segmentsOmitted: 4,
              declared: true,
            ),
          ),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
    });

    group('duplicates from one sender', () {
      test('the half carrying more speech wins, even if it came later', () {
        // An empty half written first must not hide the real one written after
        // the drain. Earliest-wins would do exactly that.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(alice, texts: const [], ts: 100),
            _candidate(alice, texts: ['hola', 'que tal'], ts: 900),
          ],
          expectedSenders: [alice],
        );

        expect(_halfFor(transcript, alice).segments.map((s) => s.text), [
          'hola',
          'que tal',
        ]);
      });

      test('a self-declared count cannot beat actual content', () {
        // The accounting describes a half; it does not authenticate one.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(
              alice,
              texts: const [],
              ts: 100,
              accounting: const HalfAccounting(
                chunksCaptured: 999,
                chunksTranscribed: 999,
                declared: true,
              ),
            ),
            _candidate(alice, texts: ['la verdad'], ts: 900),
          ],
          expectedSenders: [alice],
        );

        expect(_halfFor(transcript, alice).segments.map((s) => s.text), [
          'la verdad',
        ]);
      });

      test('equal content falls back to the earlier event', () {
        // The two must be DISTINGUISHABLE and the same length, or reversing the
        // tie-break would still pass and the test would prove nothing.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(alice, texts: ['tarde'], ts: 900),
            _candidate(alice, texts: ['antes'], ts: 100),
          ],
          expectedSenders: [alice],
        );

        expect(_halfFor(transcript, alice).segments.single.text, 'antes');
      });

      test('a half padded by repeating itself does not win', () {
        // Most-content-wins, naively on raw length, let a buggy or modified
        // client beat the truthful half just by duplicating its text.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(alice, texts: ['hello'], ts: 100),
            _candidate(alice, texts: ['hello', 'hello', 'hello'], ts: 200),
          ],
          expectedSenders: [alice],
        );

        expect(_halfFor(transcript, alice).segments, hasLength(1));
      });

      test('one half per sender, never two', () {
        final transcript = assembleTranscript(
          candidates: [
            _candidate(alice, ts: 100),
            _candidate(alice, ts: 200),
            _candidate(alice, ts: 300),
          ],
          expectedSenders: [alice],
        );

        expect(
          transcript.halves.where((h) => h.senderId == alice),
          hasLength(1),
        );
      });
    });

    test('a non-participant gets no section at all', () {
      // This test previously asserted the opposite -- that an unexpected sender
      // was "odd enough to show". That was wrong: a transcript event from
      // someone who was not in the call is a bug or an attack, and giving it a
      // section lends it the standing of a real half. It also let one room
      // member force unbounded sections by writing under many sender ids.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(alice),
          _candidate('@mallory:evil.com', texts: ['I was never here']),
        ],
        expectedSenders: [alice],
      );

      expect(transcript.halves.map((h) => h.senderId), [alice]);
    });

    test('expected senders keep their order across reads', () {
      final transcript = assembleTranscript(
        candidates: [_candidate(bob), _candidate(alice)],
        expectedSenders: [alice, bob],
      );

      expect(transcript.halves.map((h) => h.senderId), [alice, bob]);
    });

    test('a half cannot be mutated by a caller', () {
      final transcript = assembleTranscript(
        candidates: [_candidate(alice)],
        expectedSenders: [alice],
      );

      expect(
        () => _halfFor(
          transcript,
          alice,
        ).segments.add(const TranscriptSegment('injected')),
        throwsUnsupportedError,
      );
    });

    test('junk values are not a declaration, even with every key present', () {
      // Key presence alone let hostile malformed content -- '1' as a string,
      // 'yes' for a bool -- parse to optimistic defaults while still counting
      // as declared, so an empty half could be shown complete.
      final accounting = HalfAccounting.fromJson(const {
        'chunks_captured': '1',
        'chunks_transcribed': '1',
        'drain_complete': 'yes',
        'truncated': 'no',
        'segments_omitted': '0',
      });

      expect(accounting.declared, isFalse);
      expect(accounting.writerAdmitsGaps, isTrue);
    });

    test(
      'an accounting missing truncated/segments_omitted is not complete',
      () {
        final accounting = HalfAccounting.fromJson(const {
          'chunks_captured': 1,
          'chunks_transcribed': 1,
          'drain_complete': true,
        });

        expect(accounting.declared, isFalse);
        expect(accounting.writerAdmitsGaps, isTrue);
      },
    );

    test('a PARTIAL accounting is not a declaration', () {
      // chunks_captured alone used to count as a full declaration, so the
      // fields it omitted defaulted to optimistic values and the half read
      // complete -- turning silence into an assertion.
      final transcript = assembleTranscript(
        candidates: [
          TranscriptCandidate(
            senderId: alice,
            originServerTs: 100,
            segments: const [TranscriptSegment('algo')],
            accounting: HalfAccounting.fromJson(const {'chunks_captured': 2}),
          ),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
    });

    test('a writer that asserted nothing is not presented as complete', () {
      // An older or foreign client omits the accounting entirely. Absence of an
      // assertion is not an assertion of completeness, and reading it as one
      // would put a claim in that writer's mouth it never made.
      final transcript = assembleTranscript(
        candidates: [
          TranscriptCandidate(
            senderId: alice,
            originServerTs: 100,
            segments: const [TranscriptSegment('algo')],
            accounting: HalfAccounting.fromJson(const {}),
          ),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
    });
  });

  group('HalfAccounting.fromJson', () {
    test('tolerates a malformed shape rather than throwing', () {
      expect(HalfAccounting.fromJson(null).chunksCaptured, 0);
      expect(HalfAccounting.fromJson('nonsense').chunksCaptured, 0);
      expect(
        HalfAccounting.fromJson({'chunks_captured': 'lots'}).chunksCaptured,
        0,
      );
    });

    test('a missing drain flag reads as unknown, and unknown is not fine', () {
      // Absent must not be optimistic: a foreign or older writer that says
      // nothing about its drain should not be presented as complete.
      expect(HalfAccounting.fromJson({}).drainComplete, isTrue);
      expect(
        HalfAccounting.fromJson({'drain_complete': false}).drainComplete,
        isFalse,
      );
    });

    test('a half claiming more transcribed than captured is INCOHERENT, '
        'not clamped into looking complete', () {
      // This test previously asserted the opposite -- that clamping made the
      // half read complete. That was the bug: clamping a nonsense claim into
      // shape gave a broken event more credibility than a truthful one.
      final accounting = HalfAccounting.fromJson({
        'chunks_captured': 2,
        'chunks_transcribed': 99,
      });

      expect(
        accounting.chunksTranscribed,
        2,
        reason: 'still clamped for display',
      );
      expect(accounting.incoherent, isTrue);
      expect(accounting.writerAdmitsGaps, isTrue);
    });

    test('omitted segments alone mean the writer admits gaps', () {
      // segments_omitted used to be ignored unless `truncated` was also set,
      // so a writer that dropped speech and said so could still read complete.
      final accounting = HalfAccounting.fromJson({
        'chunks_captured': 2,
        'chunks_transcribed': 2,
        'segments_omitted': 4,
        'drain_complete': true,
      });

      expect(accounting.writerAdmitsGaps, isTrue);
    });

    test('round-trips its own json', () {
      const accounting = HalfAccounting(
        chunksCaptured: 4,
        chunksTranscribed: 3,
        truncated: true,
        segmentsOmitted: 2,
        drainComplete: false,
      );
      final parsed = HalfAccounting.fromJson(accounting.toJson());

      expect(parsed.chunksCaptured, 4);
      expect(parsed.chunksTranscribed, 3);
      expect(parsed.truncated, isTrue);
      expect(parsed.segmentsOmitted, 2);
      expect(parsed.drainComplete, isFalse);
    });
  });
}
