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

    test(
      'silence is not a gap: fewer transcribed than captured is COMPLETE',
      () {
        // The most common shape of a real call. Inferring loss from
        // transcribed < captured marked nearly every transcript incomplete,
        // which leaves the flag meaning nothing when a half really is short.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(
              alice,
              accounting: const HalfAccounting(
                chunksCaptured: 5,
                chunksTranscribed: 2,
                chunksLost: 0,
                declared: true,
              ),
            ),
          ],
          expectedSenders: [alice],
        );

        expect(_halfFor(transcript, alice).state, HalfState.present);
      },
    );

    test('transcribed plus lost exceeding captured is INCOHERENT', () {
      // The coherence rule is about the total, not one count: a half claiming
      // it captured 3 and then accounting for 5 of them is nonsense whichever
      // count carries the excess.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            accounting: HalfAccounting.fromJson(const {
              'chunks_captured': 3,
              'chunks_transcribed': 3,
              'chunks_lost': 2,
              'truncated': false,
              'segments_omitted': 0,
              'drain_complete': true,
            }),
          ),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).accounting.incoherent, isTrue);
      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
    });

    test('a chunk actually LOST makes the half incomplete', () {
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            accounting: const HalfAccounting(
              chunksCaptured: 5,
              chunksTranscribed: 4,
              chunksLost: 1,
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

      test('a genuinely repeated utterance is NOT discarded', () {
        // This test previously asserted the opposite -- that a half repeating
        // its own text should lose, to defend against padding. That defence
        // cost real speech: people repeat themselves, and de-duplicating made
        // the fuller half tie with a shorter earlier one and lose. The padding
        // it guarded against is not a threat, because both candidates come
        // from the same account, which can already write any single half it
        // likes.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(alice, texts: ['yes'], ts: 100),
            _candidate(alice, texts: ['yes', 'yes'], ts: 200),
          ],
          expectedSenders: [alice],
        );

        expect(_halfFor(transcript, alice).segments.map((s) => s.text), [
          'yes',
          'yes',
        ]);
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

    test('a participant listed twice still gets one section', () {
      final transcript = assembleTranscript(
        candidates: [_candidate(alice)],
        expectedSenders: [alice, alice],
      );

      expect(transcript.halves, hasLength(1));
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

    test('negative counts are not a declaration', () {
      // -1 is an int, so a type-only check accepted it, clamped it to zero, and
      // assembled a COMPLETE silent half out of hostile content.
      final accounting = HalfAccounting.fromJson(const {
        'chunks_captured': -1,
        'chunks_transcribed': -1,
        'drain_complete': true,
        'truncated': false,
        'segments_omitted': 0,
      });

      expect(accounting.declared, isFalse);
      expect(accounting.writerAdmitsGaps, isTrue);
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

  group('when the participant list is a guess, not an answer', () {
    TranscriptCandidate spoke(String sender) => _candidate(
      sender,
      texts: const ['palabras de verdad'],
      accounting: const HalfAccounting(
        chunksCaptured: 1,
        chunksTranscribed: 1,
        declared: true,
      ),
    );

    test('a half we cannot place is not discarded in silence', () {
      // The failure this design exists to prevent, from the direction it did
      // not cover. Not "we said they were silent when we could not read
      // them", but "we read them, could not place them, and said nothing at
      // all" -- while reporting the read as complete.
      final transcript = assembleTranscript(
        candidates: [spoke(bob)],
        expectedSenders: [alice],
        participantsKnown: false,
      );

      expect(transcript.readerStoppedEarly, isTrue);
      expect(
        _halfFor(transcript, alice).state,
        HalfState.incomplete,
        reason: 'we cannot say alice was absent while holding an unplaced half',
      );
    });

    test('a guess that placed everything still concludes normally', () {
      // The degradation must not fire just because the list was a guess. A
      // guess that turned out to cover everything read is as good as an
      // answer, and hedging every transcript would empty the flag of meaning.
      final transcript = assembleTranscript(
        candidates: [spoke(alice)],
        expectedSenders: [alice, bob],
        participantsKnown: false,
      );

      expect(transcript.readerStoppedEarly, isFalse);
      expect(_halfFor(transcript, alice).state, HalfState.present);
      expect(_halfFor(transcript, bob).state, HalfState.absent);
    });

    test('a KNOWN list still drops a stranger without hedging', () {
      // The anti-injection rule is the reason this function filters at all,
      // and it has to keep working: a half from somebody who was not on the
      // call gets no section, and the real halves stay conclusive.
      final transcript = assembleTranscript(
        candidates: [spoke(alice), spoke('@stranger:evil.example')],
        expectedSenders: [alice, bob],
      );

      expect(transcript.halves.map((h) => h.senderId), [alice, bob]);
      expect(transcript.readerStoppedEarly, isFalse);
      expect(_halfFor(transcript, alice).state, HalfState.present);
    });

    test('a capped read still cannot conclude, guess or not', () {
      // The two reasons a conclusion is unsafe are independent, and either
      // alone is enough.
      final transcript = assembleTranscript(
        candidates: [spoke(alice)],
        expectedSenders: [alice, bob],
        exhausted: false,
      );

      expect(transcript.readerStoppedEarly, isTrue);
      expect(_halfFor(transcript, bob).state, HalfState.incomplete);
    });
  });

  group('a microphone that never opened', () {
    test('is not reported as a speaker who said nothing', () {
      // The two arrive here identically -- zero chunks captured -- and they
      // are completely different facts. A muted speaker really did say
      // nothing. A device whose microphone was refused knows nothing about
      // the speaker at all, and saying they were silent is a confident claim
      // about a person sourced entirely from our own failure.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            texts: const [],
            accounting: const HalfAccounting(
              chunksCaptured: 0,
              chunksTranscribed: 0,
              captureRefused: true,
              declared: true,
            ),
          ),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
    });

    test('a genuinely muted speaker still reads as having said nothing', () {
      // The counterweight. This case is deliberate and must keep working, or
      // every silent half would hedge and the distinction would be worthless.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            texts: const [],
            accounting: const HalfAccounting(
              chunksCaptured: 0,
              chunksTranscribed: 0,
              declared: true,
            ),
          ),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).state, HalfState.present);
    });

    test('the flag survives the wire', () {
      final json = const HalfAccounting(
        chunksCaptured: 0,
        chunksTranscribed: 0,
        captureRefused: true,
        declared: true,
      ).toJson();

      expect(HalfAccounting.fromJson(json).captureRefused, isTrue);
      expect(HalfAccounting.fromJson(json).writerAdmitsGaps, isTrue);
    });

    test('a half that omits the flag is not a full declaration', () {
      // Same rule as every other accounting field: silence about it is an
      // absence of assertion, not an assertion of "the microphone was fine".
      final json = Map<String, dynamic>.from(
        const HalfAccounting(chunksCaptured: 1, chunksTranscribed: 1).toJson(),
      )..remove('capture_refused');

      expect(HalfAccounting.fromJson(json).declared, isFalse);
    });
  });

  group('why a half is not clean', () {
    HalfIssue issueOf(HalfAccounting accounting, {bool exhausted = true}) =>
        assembleTranscript(
          candidates: [_candidate(alice, accounting: accounting)],
          expectedSenders: [alice],
          exhausted: exhausted,
        ).halves.single.issue;

    test('a clean half has no issue', () {
      expect(
        issueOf(
          const HalfAccounting(
            chunksCaptured: 2,
            chunksTranscribed: 2,
            declared: true,
          ),
        ),
        HalfIssue.none,
      );
    });

    test('each cause is reported as itself', () {
      // The point of keeping this at all: several different failures reach the
      // same state, so the state alone cannot answer "why did it say that".
      expect(
        issueOf(const HalfAccounting(captureRefused: true, declared: true)),
        HalfIssue.microphoneRefused,
      );
      expect(
        issueOf(
          const HalfAccounting(
            chunksCaptured: 3,
            chunksTranscribed: 1,
            chunksLost: 2,
            declared: true,
          ),
        ),
        HalfIssue.audioLost,
      );
      expect(
        issueOf(
          const HalfAccounting(
            chunksCaptured: 1,
            chunksTranscribed: 1,
            truncated: true,
            segmentsOmitted: 9,
            declared: true,
          ),
        ),
        HalfIssue.tooLongToSend,
      );
      expect(
        issueOf(
          const HalfAccounting(
            chunksCaptured: 1,
            chunksTranscribed: 1,
            drainComplete: false,
            declared: true,
          ),
        ),
        HalfIssue.drainAbandoned,
      );
      expect(issueOf(const HalfAccounting()), HalfIssue.writerSaidNothing);
      expect(
        issueOf(const HalfAccounting(declared: true, incoherent: true)),
        HalfIssue.accountingImpossible,
      );
    });

    test('a speaker with no half at all is named as such', () {
      final transcript = assembleTranscript(
        candidates: const [],
        expectedSenders: [alice],
      );

      expect(transcript.halves.single.issue, HalfIssue.neverWritten);
    });

    test('a read we cut short is OUR failure, not the writer\'s', () {
      // The distinction that makes this worth logging: the same half, read two
      // ways, reports two different causes.
      final clean = const HalfAccounting(
        chunksCaptured: 1,
        chunksTranscribed: 1,
        declared: true,
      );

      expect(issueOf(clean), HalfIssue.none);
      expect(issueOf(clean, exhausted: false), HalfIssue.couldNotRead);
    });

    test('an impossible accounting is reported before what it claims', () {
      // A half that cannot be true tells us nothing reliable about any of its
      // own fields. Reporting one of them as the cause repeats the half's own
      // nonsense back with a confident label on it.
      expect(
        issueOf(
          const HalfAccounting(
            captureRefused: true,
            declared: true,
            incoherent: true,
          ),
        ),
        HalfIssue.accountingImpossible,
      );
    });

    test('unreadable content is not reported as a size problem', () {
      expect(
        issueOf(
          const HalfAccounting(
            chunksCaptured: 2,
            chunksTranscribed: 2,
            truncated: true,
            declared: true,
            unreadableContent: true,
          ),
        ),
        HalfIssue.contentUnreadable,
      );
    });

    test('our own failure is reported ahead of the writer\'s admissions', () {
      // A half can carry several at once. Only one is reported, and it is the
      // one somebody reading a bug report can act on.
      expect(
        issueOf(
          const HalfAccounting(
            captureRefused: true,
            drainComplete: false,
            declared: true,
          ),
        ),
        HalfIssue.microphoneRefused,
      );
    });
  });
}
