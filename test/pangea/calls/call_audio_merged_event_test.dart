// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';

const _callKey = '\$membership:example.com';
const _eventA = '\$eventA:example.com';
const _eventB = '\$eventB:example.com';
const _eventC = '\$eventC:example.com';

CallAudioMergedContent _content({
  String callKey = _callKey,
  String url = 'mxc://example.com/merged123',
  String mimetype = 'audio/wav',
  int size = 8192,
  int durationMs = 60000,
  int sampleRate = 48000,
  int channels = 1,
  String codec = kCallAudioCodec,
  int? mergedStartSfuMs,
  List<String> sourceEventIds = const [_eventA, _eventB],
}) => CallAudioMergedContent(
  callKey: callKey,
  url: url,
  mimetype: mimetype,
  size: size,
  durationMs: durationMs,
  sampleRate: sampleRate,
  channels: channels,
  codec: codec,
  mergedStartSfuMs: mergedStartSfuMs,
  sourceEventIds: sourceEventIds,
);

void main() {
  group('CallAudioMergedContent json', () {
    test('round-trips everything a reader depends on', () {
      final parsed = CallAudioMergedContent.fromJson(
        _content(mergedStartSfuMs: 1787994000000).toJson(),
      )!;

      expect(parsed.callKey, _callKey);
      expect(parsed.url, 'mxc://example.com/merged123');
      expect(parsed.mimetype, 'audio/wav');
      expect(parsed.size, 8192);
      expect(parsed.durationMs, 60000);
      expect(parsed.sampleRate, 48000);
      expect(parsed.channels, 1);
      expect(parsed.codec, kCallAudioCodec);
      expect(parsed.mergedStartSfuMs, 1787994000000);
      expect(parsed.sourceEventIds, [_eventA, _eventB]);
    });

    test('carries the relation that makes it findable', () {
      final json = _content().toJson();
      expect(json['m.relates_to'], {
        'rel_type': 'pangea.call_audio_merged',
        'event_id': _callKey,
      });
    });

    test('leaves out merged_start_sfu_ms when absent', () {
      final json = _content(mergedStartSfuMs: null).toJson();
      expect(json.containsKey('merged_start_sfu_ms'), isFalse);

      final parsed = CallAudioMergedContent.fromJson(json)!;
      expect(parsed.mergedStartSfuMs, isNull);
    });

    test('a malformed merged_start_sfu_ms is absent, not a refusal', () {
      final aString = _content().toJson();
      aString['merged_start_sfu_ms'] = 'not a number';
      expect(
        CallAudioMergedContent.fromJson(aString)!.mergedStartSfuMs,
        isNull,
      );

      final aDouble = _content().toJson();
      aDouble['merged_start_sfu_ms'] = 1.5;
      expect(
        CallAudioMergedContent.fromJson(aDouble)!.mergedStartSfuMs,
        isNull,
      );

      final aBool = _content().toJson();
      aBool['merged_start_sfu_ms'] = true;
      expect(CallAudioMergedContent.fromJson(aBool)!.mergedStartSfuMs, isNull);
    });

    test('emits source_event_ids sorted and de-duplicated', () {
      final json = _content(
        sourceEventIds: [_eventB, _eventA, _eventB],
      ).toJson();
      expect(json['source_event_ids'], [_eventA, _eventB]);
    });

    group('refuses content it cannot act on', () {
      test('no call key', () {
        final json = _content().toJson();
        json.remove('call_key');
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('an empty call key', () {
        final json = _content().toJson()..['call_key'] = '';
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('no url', () {
        final json = _content().toJson();
        json.remove('url');
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('an empty url', () {
        final json = _content().toJson()..['url'] = '';
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('no mimetype', () {
        final json = _content().toJson();
        json.remove('mimetype');
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('an empty mimetype', () {
        final json = _content().toJson()..['mimetype'] = '';
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('no codec', () {
        final json = _content().toJson();
        json.remove('codec');
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('an empty codec', () {
        final json = _content().toJson()..['codec'] = '';
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('a non-string call_key, url, mimetype, or codec, rather than '
          'guessing what a wrong-typed value meant', () {
        for (final key in ['call_key', 'url', 'mimetype', 'codec']) {
          final wrongType = _content().toJson()..[key] = 42;
          expect(
            CallAudioMergedContent.fromJson(wrongType),
            isNull,
            reason: 'a non-string $key must refuse, not coerce or throw',
          );

          final wrongCollection = _content().toJson()..[key] = <String>[];
          expect(
            CallAudioMergedContent.fromJson(wrongCollection),
            isNull,
            reason: 'a non-string $key must refuse, not coerce or throw',
          );
        }
      });

      test('a malformed or out-of-range size', () {
        final missing = _content().toJson();
        missing.remove('size');
        expect(CallAudioMergedContent.fromJson(missing), isNull);

        final badType = _content().toJson()..['size'] = 'a lot';
        expect(CallAudioMergedContent.fromJson(badType), isNull);

        final fractional = _content().toJson()..['size'] = 8192.5;
        expect(CallAudioMergedContent.fromJson(fractional), isNull);

        final negative = _content().toJson()..['size'] = -1;
        expect(CallAudioMergedContent.fromJson(negative), isNull);

        final overCeiling = _content().toJson()
          ..['size'] = CallAudioMergedContent.maxSize + 1;
        expect(CallAudioMergedContent.fromJson(overCeiling), isNull);

        // Boundary: zero and exactly the ceiling are BOTH within range and
        // must be accepted -- pins the `< 0`/`> maxSize` comparisons against
        // an off-by-one that would refuse either edge.
        final zero = _content().toJson()..['size'] = 0;
        expect(CallAudioMergedContent.fromJson(zero)!.size, 0);

        final atCeiling = _content().toJson()
          ..['size'] = CallAudioMergedContent.maxSize;
        expect(
          CallAudioMergedContent.fromJson(atCeiling)!.size,
          CallAudioMergedContent.maxSize,
        );
      });

      test('a malformed or out-of-range duration', () {
        final missing = _content().toJson();
        missing.remove('duration_ms');
        expect(CallAudioMergedContent.fromJson(missing), isNull);

        final badType = _content().toJson()..['duration_ms'] = 'a while';
        expect(CallAudioMergedContent.fromJson(badType), isNull);

        final fractional = _content().toJson()..['duration_ms'] = 60000.5;
        expect(CallAudioMergedContent.fromJson(fractional), isNull);

        final negative = _content().toJson()..['duration_ms'] = -1;
        expect(CallAudioMergedContent.fromJson(negative), isNull);

        final overCeiling = _content().toJson()
          ..['duration_ms'] = CallAudioMergedContent.maxDurationMs + 1;
        expect(CallAudioMergedContent.fromJson(overCeiling), isNull);

        // Boundary: zero and exactly the ceiling are BOTH within range.
        final zero = _content().toJson()..['duration_ms'] = 0;
        expect(CallAudioMergedContent.fromJson(zero)!.durationMs, 0);

        final atCeiling = _content().toJson()
          ..['duration_ms'] = CallAudioMergedContent.maxDurationMs;
        expect(
          CallAudioMergedContent.fromJson(atCeiling)!.durationMs,
          CallAudioMergedContent.maxDurationMs,
        );
      });

      test('a missing, non-integer, or non-positive sample rate or channel '
          'count', () {
        final missingRate = _content().toJson();
        missingRate.remove('sample_rate');
        expect(CallAudioMergedContent.fromJson(missingRate), isNull);

        final fractionalRate = _content().toJson()..['sample_rate'] = 48000.5;
        expect(CallAudioMergedContent.fromJson(fractionalRate), isNull);

        final zeroRate = _content().toJson()..['sample_rate'] = 0;
        expect(CallAudioMergedContent.fromJson(zeroRate), isNull);

        final negativeRate = _content().toJson()..['sample_rate'] = -1;
        expect(CallAudioMergedContent.fromJson(negativeRate), isNull);

        final missingChannels = _content().toJson();
        missingChannels.remove('channels');
        expect(CallAudioMergedContent.fromJson(missingChannels), isNull);

        final fractionalChannels = _content().toJson()..['channels'] = 1.5;
        expect(CallAudioMergedContent.fromJson(fractionalChannels), isNull);

        final zeroChannels = _content().toJson()..['channels'] = 0;
        expect(CallAudioMergedContent.fromJson(zeroChannels), isNull);

        final negativeChannels = _content().toJson()..['channels'] = -1;
        expect(CallAudioMergedContent.fromJson(negativeChannels), isNull);
      });

      test('a missing source_event_ids', () {
        final json = _content().toJson();
        json.remove('source_event_ids');
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('a source_event_ids that is not a list at all', () {
        final aString = _content().toJson()
          ..['source_event_ids'] = 'not a list';
        expect(CallAudioMergedContent.fromJson(aString), isNull);

        final aMap = _content().toJson()..['source_event_ids'] = {'a': 1};
        expect(CallAudioMergedContent.fromJson(aMap), isNull);
      });

      test('an empty source_event_ids', () {
        final json = _content().toJson()..['source_event_ids'] = <String>[];
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test(
        'a source_event_ids that sanitises to empty (all blank/non-string)',
        () {
          final json = _content().toJson()
            ..['source_event_ids'] = ['', '', 42, null];
          expect(CallAudioMergedContent.fromJson(json), isNull);
        },
      );

      test('more distinct source_event_ids than maxSourceEventIds, rather than '
          'silently truncating coverage', () {
        final tooMany = [
          for (var i = 0; i < CallAudioMergedContent.maxSourceEventIds + 1; i++)
            '\$event$i:example.com',
        ];
        final json = _content().toJson()..['source_event_ids'] = tooMany;
        expect(CallAudioMergedContent.fromJson(json), isNull);
      });

      test('exactly maxSourceEventIds distinct ids is accepted (boundary)', () {
        final exactly = [
          for (var i = 0; i < CallAudioMergedContent.maxSourceEventIds; i++)
            '\$event$i:example.com',
        ];
        final json = _content().toJson()..['source_event_ids'] = exactly;
        final parsed = CallAudioMergedContent.fromJson(json)!;
        expect(parsed.sourceEventIds, hasLength(exactly.length));
      });
    });

    test('source_event_ids is sorted and de-duplicated on parse, dropping '
        'blanks and non-strings', () {
      final json = _content().toJson()
        ..['source_event_ids'] = [_eventB, '', _eventA, _eventB, 7];
      final parsed = CallAudioMergedContent.fromJson(json)!;
      expect(parsed.sourceEventIds, [_eventA, _eventB]);
    });
  });

  group('CallAudioMergedContent.coverageCardinality', () {
    test('counts the de-duplicated set, not the raw list length', () {
      final content = _content(
        sourceEventIds: [_eventA, _eventB, _eventA, _eventB],
      );
      expect(content.coverageCardinality, 2);
    });
  });

  group('CallAudioMergedContent.coverageHash', () {
    test('is stable for the same id set regardless of input order', () {
      final first = _content(sourceEventIds: [_eventA, _eventB, _eventC]);
      final second = _content(sourceEventIds: [_eventC, _eventA, _eventB]);
      expect(first.coverageHash, second.coverageHash);
    });

    test('differs for a different coverage set', () {
      final twoHalves = _content(sourceEventIds: [_eventA, _eventB]);
      final threeHalves = _content(sourceEventIds: [_eventA, _eventB, _eventC]);
      expect(twoHalves.coverageHash, isNot(threeHalves.coverageHash));
    });

    test('de-duplicates before hashing, so repeats do not change it', () {
      final once = _content(sourceEventIds: [_eventA, _eventB]);
      final repeated = _content(
        sourceEventIds: [_eventA, _eventB, _eventA, _eventA],
      );
      expect(once.coverageHash, repeated.coverageHash);
    });

    test('a set whose SINGLE id embeds the old NUL join-separator does not '
        'collide with the two ids that separator used to concatenate to the '
        'same string -- pins the length-prefixed hash against exactly the '
        'collision a bare separator-join would have produced', () {
      final oneIdContainingTheOldSeparator = _content(
        sourceEventIds: ['x\u0000y'],
      );
      final twoPlainIds = _content(sourceEventIds: ['x', 'y']);
      expect(
        oneIdContainingTheOldSeparator.coverageHash,
        isNot(twoPlainIds.coverageHash),
      );
      // Also a different cardinality, confirming these are genuinely
      // different coverage sets and not merely different-looking inputs
      // that happen to canonicalise the same way.
      expect(oneIdContainingTheOldSeparator.coverageCardinality, 1);
      expect(twoPlainIds.coverageCardinality, 2);
    });

    test('matches a golden vector -- pins the EXACT algorithm (length-prefixed '
        'UTF-8 bytes, sorted, SHA-256, hex), not merely internal self-'
        'consistency, since a DIFFERENT collision-safe scheme could otherwise '
        'satisfy every other test in this group', () {
      // Independently verified two ways: this project's own algorithm run
      // standalone, and a from-scratch Python re-implementation of the
      // documented scheme (utf8 byte length + ':' + utf8 bytes, per
      // canonical id, sorted, concatenated, sha256, hex). The non-ASCII id
      // ('café') distinguishes a UTF-8 BYTE-length prefix from a UTF-16
      // code-unit-length prefix -- 'café'.length is 4 in Dart but its utf8
      // encoding is 5 bytes, so a length-prefix bug using code units
      // instead of bytes would produce a DIFFERENT hash here.
      final content = _content(
        sourceEventIds: ['\$b:example.com', '\$a-café:example.com'],
      );
      expect(
        content.coverageHash,
        '152982e8729f7cde0205cb4256731f9c9e6c8263e0fad97ee317a284118ef7a3',
      );
    });

    test('a malformed id contributes NOTHING to the hash -- adding one to a '
        'real id must not change the hash from the real id alone, which is '
        'what actually proves it never reaches the hash (unlike comparing two '
        'malformed ids against each other, which a naive lossy encoder would '
        'ALSO make equal, by accident, without dropping either)', () {
      final loneSurrogate = String.fromCharCode(0xD800);
      final realAlone = _content(sourceEventIds: [_eventA]);
      final realPlusMalformed = _content(
        sourceEventIds: [_eventA, loneSurrogate],
      );
      expect(realPlusMalformed.coverageHash, realAlone.coverageHash);
    });
  });

  group('CallAudioMergedContent.txnId', () {
    test(
      'is identical for the same (call_key, coverage) in any input order',
      () {
        final a = CallAudioMergedContent.txnId(_callKey, [_eventA, _eventB]);
        final b = CallAudioMergedContent.txnId(_callKey, [_eventB, _eventA]);
        expect(a, b);
      },
    );

    test('is identical whether or not the input list carries a duplicate -- '
        'proves it goes through the de-duplicated coverage hash, not a plain '
        'sort of the raw list', () {
      final a = CallAudioMergedContent.txnId(_callKey, [_eventA, _eventB]);
      final withDuplicate = CallAudioMergedContent.txnId(_callKey, [
        _eventA,
        _eventB,
        _eventA,
      ]);
      expect(a, withDuplicate);
    });

    test('differs across coverage', () {
      final twoHalves = CallAudioMergedContent.txnId(_callKey, [
        _eventA,
        _eventB,
      ]);
      final threeHalves = CallAudioMergedContent.txnId(_callKey, [
        _eventA,
        _eventB,
        _eventC,
      ]);
      expect(twoHalves, isNot(threeHalves));
    });

    test('differs across call_key for the same coverage', () {
      final a = CallAudioMergedContent.txnId(_callKey, [_eventA, _eventB]);
      final b = CallAudioMergedContent.txnId('\$otherMembership:example.com', [
        _eventA,
        _eventB,
      ]);
      expect(a, isNot(b));
    });

    test('does not depend on senderId or deviceId -- it takes neither', () {
      // No sender/device parameter exists on this signature at all: the
      // static method's own arity is the guarantee that any device merging
      // the same coverage of the same call produces the same id.
      final a = CallAudioMergedContent.txnId(_callKey, [_eventA, _eventB]);
      final b = CallAudioMergedContent.txnId(_callKey, [_eventA, _eventB]);
      expect(a, b);
    });
  });

  group('CallAudioMergedContent bounded parsing of source_event_ids', () {
    test('a raw list longer than the scan bound is refused ENTIRELY, never '
        'silently truncated to whatever a partial scan happened to see', () {
      // One entry past four times the coverage ceiling -- every entry the
      // SAME id, so the true distinct coverage is trivially just one and
      // would otherwise have parsed fine. A reader that merely stopped
      // scanning early (rather than refusing outright) would silently
      // accept this as "coverage: [_eventA]" without ever having looked at
      // whether the tail of the list said something different.
      final tooManyRaw = List<String>.filled(
        CallAudioMergedContent.maxSourceEventIds * 4 + 1,
        _eventA,
      );
      final json = _content().toJson()..['source_event_ids'] = tooManyRaw;
      expect(CallAudioMergedContent.fromJson(json), isNull);
    });

    test('a raw list AT the scan bound still parses -- the ceiling refuses '
        'only what is genuinely past it', () {
      final atBoundRaw = List<String>.filled(
        CallAudioMergedContent.maxSourceEventIds * 4,
        _eventA,
      );
      final json = _content().toJson()..['source_event_ids'] = atBoundRaw;
      final parsed = CallAudioMergedContent.fromJson(json)!;
      expect(parsed.sourceEventIds, [_eventA]);
    });

    test('drops a single id longer than the per-id character ceiling rather '
        'than refusing the whole statement', () {
      final tooLong = 'x' * 600;
      final json = _content().toJson()
        ..['source_event_ids'] = [_eventA, tooLong];
      final parsed = CallAudioMergedContent.fromJson(json)!;
      expect(parsed.sourceEventIds, [_eventA]);
    });

    test('refuses a set left with NOTHING usable once every id is dropped for '
        'being over-length', () {
      final onlyTooLong = _content().toJson()
        ..['source_event_ids'] = ['x' * 600, 'y' * 600];
      expect(CallAudioMergedContent.fromJson(onlyTooLong), isNull);
    });

    test(
      'the per-id length ceiling is exactly 512: 512 is kept, 513 is dropped',
      () {
        final atLimit = 'x' * 512;
        final overLimit = 'y' * 513;
        final json = _content().toJson()
          ..['source_event_ids'] = [atLimit, overLimit];
        final parsed = CallAudioMergedContent.fromJson(json)!;
        expect(parsed.sourceEventIds, [atLimit]);
      },
    );

    test('drops a malformed (lone-surrogate) id rather than letting it collide '
        'in the hash, and a set left with nothing usable is refused', () {
      final loneSurrogate = String.fromCharCode(0xD800);
      final withRealId = _content().toJson()
        ..['source_event_ids'] = [_eventA, loneSurrogate];
      final parsed = CallAudioMergedContent.fromJson(withRealId)!;
      expect(parsed.sourceEventIds, [_eventA]);

      final onlyMalformed = _content().toJson()
        ..['source_event_ids'] = [loneSurrogate];
      expect(CallAudioMergedContent.fromJson(onlyMalformed), isNull);
    });
  });

  group(
    'CallAudioMergedContent.coverageHash malformed-id collision safety',
    () {
      test('a malformed (lone-surrogate) id never becomes a distinct coverage '
          'entry, which is what keeps it from colliding with a DIFFERENT '
          'malformed id that would encode to the identical UTF-8 replacement '
          'bytes', () {
        // 0xD800 and 0xD801 are both unpaired UTF-16 surrogate halves; Dart's
        // utf8.encode substitutes the SAME U+FFFD replacement bytes for
        // either one rather than throwing (verified separately). Naively
        // hashing whatever bytes each one encodes to would make these two
        // GENUINELY DIFFERENT ids collide. The actual defense is upstream of
        // that: canonicalSourceEventIds drops a malformed id outright, so
        // NEITHER ever becomes a distinct entry to hash -- both canonicalise
        // to the SAME empty coverage, which is safe precisely because empty
        // coverage is refused before it is ever sent (see fromJson and
        // writeCallAudioMergedEvent), not because the two malformed strings
        // were somehow told apart.
        final a = _content(sourceEventIds: [String.fromCharCode(0xD800)]);
        final b = _content(sourceEventIds: [String.fromCharCode(0xD801)]);
        expect(a.coverageCardinality, 0);
        expect(b.coverageCardinality, 0);
        expect(a.coverageHash, b.coverageHash);
      });
    },
  );
}
