import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';

const alice = '@alice:example.com';
const bob = '@bob:example.com';

TranscriptCandidate _candidate(
  String sender, {
  List<String> texts = const ['hola'],
  List<TranscriptSegment>? segments,
  int ts = 1000,
  HalfAccounting accounting = const HalfAccounting(
    chunksCaptured: 2,
    chunksTranscribed: 2,
    declared: true,
  ),
  ClockAnchor? anchor,
}) => TranscriptCandidate(
  senderId: sender,
  originServerTs: ts,
  segments: segments ?? [for (final text in texts) TranscriptSegment(text)],
  accounting: accounting,
  clockAnchor: anchor,
);

/// A device whose clock ran [aheadMs] ahead of the SFU's at join.
ClockAnchor _skewed(int aheadMs) =>
    ClockAnchor(sfuMs: _sfuJoin, deviceMs: _sfuJoin + aheadMs);

/// The SFU's clock at join. A real instant, because the reader refuses a
/// reading that could not be one.
const _sfuJoin = 1787994000000;

/// A segment that knows when it was said.
TranscriptSegment _placed(String text, int atMs) =>
    TranscriptSegment(text, atMs: atMs);

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

      test('a positioned half beats its own coarse untimed duplicate', () {
        // `contentLength` sums segment texts and counts no separators, so
        // ["hello world"] measures 11 and ["hello", "world"] measures 10.
        // Those are the SAME WORDS, and they are exactly the pair this step
        // exists for: a newer half split finely by timings against an older one
        // that was not. Below the length test, the old half wins on a
        // difference that is an artefact of how it was cut.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(
              alice,
              segments: const [TranscriptSegment('hello world')],
              ts: 100,
            ),
            _candidate(
              alice,
              segments: [_placed('hello', 1000), _placed('world', 2000)],
              ts: 900,
            ),
          ],
          expectedSenders: [alice],
        );

        expect(_halfFor(transcript, alice).segments.map((s) => s.atMs), [
          1000,
          2000,
        ]);
      });

      test('a same-LENGTH but different half does not win on being placed', () {
        // Equal length is two halves that happen to be the same size, which is
        // not the same words. Letting a positioned one win there would change
        // what the transcript SAYS rather than only its order.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(
              alice,
              segments: const [TranscriptSegment('antes')],
              ts: 100,
            ),
            _candidate(alice, segments: [_placed('tarde', 1000)], ts: 900),
          ],
          expectedSenders: [alice],
        );

        expect(
          _halfFor(transcript, alice).segments.single.text,
          'antes',
          reason: 'the earlier event still wins the tie',
        );
      });

      test('a placed duplicate does not displace a different ACCOUNTING', () {
        // Requiring the accountings to match is what stops this step changing
        // the DIAGNOSIS to buy a timeline. Two halves that are both merely "not
        // clean" are not interchangeable: a positioned one that lost a chunk
        // must not displace an unpositioned one that is whole.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(
              alice,
              segments: const [TranscriptSegment('hola')],
              ts: 100,
            ),
            _candidate(
              alice,
              segments: [_placed('hola', 1000)],
              ts: 900,
              accounting: const HalfAccounting(
                chunksCaptured: 2,
                chunksTranscribed: 1,
                chunksLost: 1,
                declared: true,
              ),
            ),
          ],
          expectedSenders: [alice],
        );

        expect(_halfFor(transcript, alice).segments.single.atMs, isNull);
        expect(_halfFor(transcript, alice).accounting.chunksLost, 0);
      });

      test('a placed duplicate with jumbled positions does not win', () {
        // Eligible by the FULL test, not merely "carries some at_ms".
        // Otherwise a same-text half with jumbled positions replaces a sound
        // one and then fails the render gate anyway, and the timeline is lost
        // to a half that could never have shown it.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(
              alice,
              segments: const [
                TranscriptSegment('hola'),
                TranscriptSegment('que tal'),
              ],
              ts: 100,
            ),
            _candidate(
              alice,
              segments: [_placed('hola', 5000), _placed('que tal', 1000)],
              ts: 900,
            ),
          ],
          expectedSenders: [alice],
        );

        expect(
          _halfFor(transcript, alice).segments.map((s) => s.atMs),
          [null, null],
          reason: 'the earlier event keeps the slot',
        );
      });
    });

    group('when the timeline may render', () {
      test('both halves placed and in order', () {
        final transcript = assembleTranscript(
          candidates: [
            _candidate(
              alice,
              segments: [_placed('hola', 1000), _placed('muy bien', 9000)],
            ),
            _candidate(bob, segments: [_placed('que tal', 5000)]),
          ],
          expectedSenders: [alice, bob],
        );

        expect(transcript.timelineEligible, isTrue);
      });

      test('one unpositioned chunk drops the whole call to per-speaker', () {
        // Part of a call in order and part of it not is worse than neither: the
        // reader cannot tell which turns were placed and which were guessed.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(alice, segments: [_placed('hola', 1000)]),
            _candidate(
              bob,
              segments: [
                _placed('que tal', 2000),
                const TranscriptSegment('y luego'),
              ],
            ),
          ],
          expectedSenders: [alice, bob],
        );

        expect(_halfFor(transcript, alice).timelineEligible, isTrue);
        expect(_halfFor(transcript, bob).timelineEligible, isFalse);
        expect(transcript.timelineEligible, isFalse);
      });

      test('positions that go backwards render per-speaker', () {
        // Presence alone is not enough. A half with every position filled but
        // jumbled would render that speaker's own words out of order, with full
        // confidence. Monotonicity is what this writer guarantees, so a half
        // that fails it was not written by this code.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(
              alice,
              segments: [_placed('luego', 5000), _placed('primero', 1000)],
            ),
          ],
          expectedSenders: [alice],
        );

        expect(transcript.timelineEligible, isFalse);
        expect(
          _halfFor(transcript, alice).segments.map((s) => s.text),
          ['luego', 'primero'],
          reason: 'and the words are untouched either way',
        );
      });

      test('a speaker who said nothing does not hold the timeline back', () {
        // A silent half has no turn that could land in the wrong place.
        final transcript = assembleTranscript(
          candidates: [
            _candidate(alice, segments: [_placed('hola', 1000)]),
            _candidate(bob, segments: const []),
          ],
          expectedSenders: [alice, bob],
        );

        expect(transcript.timelineEligible, isTrue);
      });
    });

    group('HalfAccounting as a value', () {
      HalfAccounting parsed({int lost = 0}) => HalfAccounting.fromJson({
        'chunks_captured': 2,
        'chunks_transcribed': 2,
        'chunks_lost': lost,
        'capture_refused': false,
        'truncated': false,
        'segments_omitted': 0,
        'drain_complete': true,
      });

      test('two accountings with the same fields are equal', () {
        // Without this the duplicate rule above is dead code that READS as
        // protection: `==` would be identity, and two halves parsed from two
        // events could never compare equal.
        expect(
          identical(parsed(), parsed()),
          isFalse,
          reason: 'two real instances, or this proves nothing',
        );
        expect(parsed(), parsed());
        expect(parsed().hashCode, parsed().hashCode);
      });

      test('a difference in any field is a difference', () {
        expect(parsed(), isNot(parsed(lost: 1)));
        expect(
          const HalfAccounting(declared: true),
          isNot(const HalfAccounting(declared: true, unreadableContent: true)),
          reason: 'the reader-side fields count too',
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

    test('a half we cannot place is dropped, and the read says so', () {
      // Two claims, and the first was never asserted.
      //
      // This test was written for an older rule, where an unplaceable half is
      // what triggered the hedge. That rule is gone: `canConclude` now asks
      // only whether the read finished and whether we can name who was on the
      // call, because the old one caught a peer who WROTE something and
      // missed entirely a peer who wrote nothing. So the hedge below no
      // longer depends on bob at all -- it follows from the participants
      // being a guess -- and asserting it alone proved nothing about the
      // half this test is named for.
      final transcript = assembleTranscript(
        candidates: [spoke(bob)],
        expectedSenders: [alice],
        participantsKnown: false,
      );

      // The claim that matters and was missing: bob's words do NOT reach the
      // screen. Only a named participant gets a section, which is what stops
      // a stranger writing themselves one -- and it holds even when the list
      // of names is a guess, because a guess is not permission.
      expect(transcript.halves.map((h) => h.senderId), [alice]);
      expect(
        transcript.halves.single.segments,
        isEmpty,
        reason: "bob's speech must not appear under alice",
      );

      // And the read does not present itself as whole while that is true.
      expect(transcript.readerStoppedEarly, isTrue);
      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
    });

    test('a peer we cannot name and who wrote nothing is not "absent"', () {
      // The case the previous rule could not see, and the reason it is gone.
      //
      // It degraded only when an UNPLACEABLE half turned up while the
      // participants were unknown -- which catches a peer who WROTE
      // something, since their half cannot be placed, and misses entirely the
      // peer who wrote nothing. With nobody identifiable there is then no
      // unplaceable half and no second sender to report, so the screen showed
      // one side of a conversation and said nothing was missing.
      final transcript = assembleTranscript(
        candidates: [spoke(alice)],
        expectedSenders: [alice],
        participantsKnown: false,
      );

      expect(
        transcript.readerStoppedEarly,
        isTrue,
        reason: 'not knowing who was on the call is itself a reason to hedge',
      );
      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
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

    test('OUR ceiling is not the writer saying it could not fit', () {
      // Both set `truncated`, because the half reads as incomplete either
      // way. Only one of them is ours, and reporting our ceiling as the
      // writer omitting segments to fit sends whoever reads the bug report to
      // the wrong device. Second time `truncated` standing for two causes has
      // cost a wrong diagnosis in this feature.
      const writersOwn = HalfAccounting(
        chunksCaptured: 4,
        chunksTranscribed: 4,
        truncated: true,
        segmentsOmitted: 3,
        declared: true,
      );

      expect(issueOf(writersOwn), HalfIssue.tooLongToSend);
      expect(issueOf(writersOwn.readerTruncated()), HalfIssue.tooLongToRead);
    });

    test(
      'a half that never arrived reports no claim the writer never made',
      () {
        // Nothing came from bob, and we cannot name who was on the call, so we
        // cannot say he was silent. Every field of his accounting is a default
        // WE constructed -- and `declared` being false then read as the writer
        // saying nothing about its own capture, which is a statement about a
        // person produced entirely from a placeholder of ours. `declared` was
        // standing for two things again: "they sent junk" and "we invented
        // this".
        final transcript = assembleTranscript(
          candidates: [_candidate(alice)],
          expectedSenders: [alice, bob],
          participantsKnown: false,
        );

        final missing = _halfFor(transcript, bob);
        expect(missing.state, HalfState.incomplete);
        expect(missing.issue, HalfIssue.participantsUnknown);
      },
    );

    test('not knowing who spoke does not mask what a half admits', () {
      // Whether the transcript may be called whole and whether OUR read of
      // this half fell short are different questions. Deriving the second
      // from the first made every half of a call with an unnameable peer
      // report "we could not read it" ahead of the concrete thing it said.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            accounting: const HalfAccounting(
              chunksCaptured: 4,
              chunksTranscribed: 2,
              chunksLost: 2,
              declared: true,
            ),
          ),
        ],
        expectedSenders: [alice],
        participantsKnown: false,
      );

      final half = transcript.halves.single;
      expect(
        half.state,
        HalfState.incomplete,
        reason: 'the screen still hedges: we cannot name who was on the call',
      );
      expect(
        half.issue,
        HalfIssue.audioLost,
        reason: 'but the diagnosis keeps the fact somebody can act on',
      );
    });

    test('an impossible accounting does not cast doubt on OUR read', () {
      // Nonsense numbers outrank everything DERIVED from them, and nothing
      // else. This check used to sit above our own failures too, so a read we
      // cut short was reported as the writer's arithmetic being impossible --
      // which is true, and is not the thing the person reading it can act on.
      // Their numbers say nothing about whether we finished looking.
      const nonsense = HalfAccounting(
        chunksCaptured: 1,
        chunksTranscribed: 5,
        declared: true,
        incoherent: true,
      );

      expect(issueOf(nonsense), HalfIssue.accountingImpossible);
      expect(issueOf(nonsense, exhausted: false), HalfIssue.couldNotRead);
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

      // The combination the ordering was actually wrong about. A cut-short
      // read alongside a writer admission used to report the ADMISSION,
      // because both set HalfState.incomplete and the reader-side check sat
      // last -- so nothing said we had not finished looking, and the bug
      // report pointed at the other device.
      const admits = HalfAccounting(
        chunksCaptured: 4,
        chunksTranscribed: 2,
        chunksLost: 2,
        declared: true,
      );

      expect(issueOf(admits), HalfIssue.audioLost);
      expect(issueOf(admits, exhausted: false), HalfIssue.couldNotRead);
    });
  });

  group('ClockAnchor', () {
    test('an offset is how far the DEVICE ran ahead of the SFU', () {
      // The sign is load-bearing: the reader SUBTRACTS this to move a half
      // onto the shared clock, so getting it backwards doubles the skew
      // instead of removing it.
      expect(_skewed(30000).offsetMs, 30000);
      expect(_skewed(-30000).offsetMs, -30000);
      expect(_skewed(0).offsetMs, 0);
    });

    test('round-trips its own json', () {
      final anchor = _skewed(1500);
      expect(ClockAnchor.fromJson(anchor.toJson()), anchor);
    });

    test('the field names are the wire contract', () {
      // Named here so a rename cannot pass silently: the whole point of the
      // fields is that another client, and an older build of this one, reads
      // them. A parse that quietly stops matching costs the correction on
      // every call between two versions.
      expect(_skewed(1500).toJson(), {
        'sfu_joined_at_ms': _sfuJoin,
        'device_joined_at_ms': _sfuJoin + 1500,
      });
    });

    test('a zero SFU reading is refused, not believed', () {
      // Zero is the protocol default for `joinedAt`. A server that never
      // stamped it reads as 1970, and the offset against 1970 is this
      // device's ENTIRE clock -- some fifty-six years of "skew" applied to
      // one speaker's half.
      expect(ClockAnchor.of(sfuMs: 0, deviceMs: _sfuJoin), isNull);
      expect(ClockAnchor.of(sfuMs: _sfuJoin, deviceMs: 0), isNull);
    });

    test('a negative or absurd reading is refused', () {
      expect(ClockAnchor.of(sfuMs: -1, deviceMs: _sfuJoin), isNull);
      expect(ClockAnchor.of(sfuMs: _sfuJoin, deviceMs: -1), isNull);
      expect(
        ClockAnchor.of(sfuMs: ClockAnchor.clockCeilingMs, deviceMs: _sfuJoin),
        isNull,
      );
      expect(
        ClockAnchor.of(
          sfuMs: _sfuJoin,
          // Beyond what a double holds exactly, which is where the
          // subtraction stops being arithmetic and starts being rounding.
          deviceMs: TranscriptSegment.atMsCeiling,
        ),
        isNull,
      );
    });

    test('hostile content yields no anchor rather than an exception', () {
      // Room content is somebody else's word. A throw here would take down a
      // transcript whose words are perfectly readable, to protect an ordering.
      expect(ClockAnchor.fromJson(const {}), isNull);
      expect(
        ClockAnchor.fromJson(const {
          'sfu_joined_at_ms': 'soon',
          'device_joined_at_ms': 'later',
        }),
        isNull,
      );
      expect(
        ClockAnchor.fromJson(const {
          'sfu_joined_at_ms': 1.5,
          'device_joined_at_ms': 2.5,
        }),
        isNull,
      );
      expect(
        ClockAnchor.fromJson(const {
          'sfu_joined_at_ms': _sfuJoin,
          'device_joined_at_ms': -5,
        }),
        isNull,
      );
    });

    test('half an anchor measures nothing, so it is no anchor', () {
      // A device time with no server time beside it is just a device time.
      // Accepting one alone would put an offset of zero on a half whose clock
      // was never compared to anything -- a claim that the two clocks agreed.
      expect(
        ClockAnchor.fromJson(const {'device_joined_at_ms': _sfuJoin}),
        isNull,
      );
      expect(
        ClockAnchor.fromJson(const {'sfu_joined_at_ms': _sfuJoin}),
        isNull,
      );
    });
  });

  group('putting both halves on one clock', () {
    test('the anchor travels from the chosen candidate onto the half', () {
      // It has to reach the HALF: the merge happens after selection, and an
      // offset that stops at the candidate is an offset the view never sees.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(alice, anchor: _skewed(30000)),
          _candidate(bob, anchor: _skewed(0)),
        ],
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, alice).clockAnchor, _skewed(30000));
      expect(_halfFor(transcript, bob).clockAnchor, _skewed(0));
    });

    test('an anchored duplicate beats an identical unanchored one', () {
      // Same words, same claims, same placeability -- one written by a build
      // that records the join clocks and one by a build that does not. Letting
      // the older copy hold the slot buries an anchor that WAS written and
      // silently reinstates the skew, and no word of the transcript turns on
      // the choice, because the two say the same thing.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(alice, ts: 100),
          _candidate(alice, ts: 900, anchor: _skewed(30000)),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).clockAnchor, _skewed(30000));
    });

    test('and the earlier copy still wins when neither is anchored', () {
      // The tie-break this sits in front of, unchanged: with nothing to choose
      // between them the earlier event keeps the slot.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(alice, ts: 900, texts: const ['later']),
          _candidate(alice, ts: 100, texts: const ['first']),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).segments.single.text, 'first');
    });

    test('but never over a copy that carries more speech', () {
      // An anchor decides ORDER. Words decide what the transcript says, and no
      // amount of the former buys any of the latter: a fuller half still wins,
      // and the call simply goes uncorrected.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(alice, texts: const ['hola', 'que tal amigo']),
          _candidate(alice, texts: const ['hola'], anchor: _skewed(30000)),
        ],
        expectedSenders: [alice],
      );

      expect(_halfFor(transcript, alice).segments, hasLength(2));
      expect(_halfFor(transcript, alice).clockAnchor, isNull);
    });

    test('a half nobody wrote asserts nothing about any clock', () {
      // The same rule as its accounting: a synthesised offset of zero would be
      // this reader claiming two clocks agreed, about a device that never told
      // us what its clock said.
      final transcript = assembleTranscript(
        candidates: [_candidate(alice, anchor: _skewed(30000))],
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, bob).clockAnchor, isNull);
    });

    test('each half is shifted by its own offset', () {
      final transcript = assembleTranscript(
        candidates: [
          _candidate(alice, anchor: _skewed(30000)),
          _candidate(bob, anchor: _skewed(-500)),
        ],
        expectedSenders: [alice, bob],
      );

      expect(transcript.clocksReconcilable, isTrue);
      expect(transcript.clockShiftFor(_halfFor(transcript, alice)), 30000);
      expect(transcript.clockShiftFor(_halfFor(transcript, bob)), -500);
    });

    test('ONE half without an anchor stops the whole correction', () {
      // All or nothing. Correcting one speaker and not the other moves them
      // relative to each other by an offset measured for only one of them --
      // we cannot bound whether that helps or harms, and a correction that
      // might invert an order which was already right is worse than none.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(alice, anchor: _skewed(30000)),
          _candidate(bob),
        ],
        expectedSenders: [alice, bob],
      );

      expect(transcript.clocksReconcilable, isFalse);
      expect(transcript.clockShiftFor(_halfFor(transcript, alice)), 0);
      expect(transcript.clockShiftFor(_halfFor(transcript, bob)), 0);
    });

    test('a SILENT half without an anchor does not stop it', () {
      // A half with no segments puts nothing on the timeline, so its clock
      // cannot move any turn. Refusing the correction over it would throw the
      // fix away in calls where it works perfectly.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(alice, anchor: _skewed(30000)),
          _candidate(bob, texts: const [], accounting: const HalfAccounting()),
        ],
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, bob).segments, isEmpty);
      expect(transcript.clocksReconcilable, isTrue);
      expect(transcript.clockShiftFor(_halfFor(transcript, alice)), 30000);
    });

    test('an absent speaker does not stop it either', () {
      final transcript = assembleTranscript(
        candidates: [_candidate(alice, anchor: _skewed(30000))],
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, bob).state, HalfState.absent);
      expect(transcript.clocksReconcilable, isTrue);
      expect(transcript.clockShiftFor(_halfFor(transcript, alice)), 30000);
    });

    test('the shift cannot reorder a half against itself', () {
      // The render gate is answered on the RAW positions and the shift is
      // applied after it, so the two have to agree. One constant subtracted
      // from every position in a half cannot reorder them -- this is the
      // property that lets the gate go on reading the raw values.
      final transcript = assembleTranscript(
        candidates: [
          _candidate(
            alice,
            segments: [
              _placed('hola', _sfuJoin),
              _placed('que tal', _sfuJoin + 6000),
            ],
            anchor: _skewed(30000),
          ),
        ],
        expectedSenders: [alice],
      );

      final half = _halfFor(transcript, alice);
      final shift = transcript.clockShiftFor(half);
      expect(half.timelineEligible, isTrue);
      expect(
        segmentsArePlaceable([
          for (final segment in half.segments)
            TranscriptSegment(segment.text, atMs: segment.atMs! - shift),
        ]),
        isTrue,
      );
    });
  });
}
