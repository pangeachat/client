import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/tokens/tokens_util.dart';

/// #8385 — a message's token list can be REPLACED in place, under an unchanged
/// event id: a language correction re-tokenizes the same text under a
/// different model, and token-info feedback re-tokenizes it outright.
///
/// `getAdjacentTokenPositions` returns INDICES INTO the list it was handed, so
/// a cache keyed on the event id alone hands the new list the old list's
/// indices — and `html_message`'s `tokens.sublist(start, end + 1)` throws
/// `RangeError (end): Only valid value is 19: 21`.

PangeaToken _token(String content, int offset, {String pos = 'NOUN'}) =>
    PangeaToken.fromJson({
      'text': {'content': content, 'offset': offset, 'length': content.length},
      'lemma': {'text': content, 'save_vocab': true, 'form': content},
      'pos': pos,
      'morph': <String, dynamic>{},
    });

/// "Guten Tag Herr Doktor" read as four words…
List<PangeaToken> _germanReading() => [
  _token('Guten', 0),
  _token('Tag', 6),
  _token('Herr', 10),
  _token('Doktor', 15),
];

/// …and the same text re-read as two, the way a different tokenizer model
/// legitimately can.
List<PangeaToken> _shorterReading() => [
  _token('Guten Tag', 0),
  _token('Herr Doktor', 10),
];

void main() {
  const eventId = r'$msg:fakeServer.notExisting';

  test('positions follow the token list, not the event id', () {
    final long = TokensUtil.instance.getAdjacentTokenPositions(
      eventId,
      _germanReading(),
    );
    expect(long, hasLength(4));

    final short = _shorterReading();
    final positions = TokensUtil.instance.getAdjacentTokenPositions(
      eventId,
      short,
    );

    // Teeth: cached on the event id alone, this returns the 4 stale positions
    // and the last one indexes past the end of the 2-token list.
    expect(positions, hasLength(2));
    for (final position in positions) {
      expect(
        position.endIndex,
        lessThan(short.length),
        reason: 'html_message slices tokens.sublist(start, end + 1)',
      );
    }
  });

  test('the same token list still comes back from cache', () {
    final tokens = _germanReading();
    final first = TokensUtil.instance.getAdjacentTokenPositions(
      eventId,
      tokens,
    );
    final second = TokensUtil.instance.getAdjacentTokenPositions(
      eventId,
      tokens,
    );
    expect(identical(first, second), isTrue);
  });

  test('a re-tokenization that keeps the token COUNT is still a different '
      'reading', () {
    // A length-only cache key would serve the stale positions here: same
    // count, different spans, so the renderer would not crash — it would
    // quietly underline and tap-target the wrong words.
    TokensUtil.instance.getAdjacentTokenPositions(eventId, [
      _token('Guten', 0),
      _token('Tag', 6),
    ]);
    final positions = TokensUtil.instance.getAdjacentTokenPositions(eventId, [
      _token('Hallo', 0),
      _token('Welt', 6),
    ]);

    expect(positions.map((p) => p.token!.text.content), ['Hallo', 'Welt']);
  });
}
