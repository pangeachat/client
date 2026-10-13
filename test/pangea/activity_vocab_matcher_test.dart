import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_vocab_matcher.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';

/// `ActivityVocabMatcher` is the one rule behind the gold target-vocab
/// highlight and the used-vocab chips (issue #9386): single-word entries
/// match a token by lemma, phrase entries match a run of consecutive tokens
/// by text or lemma. Activity vocab routinely carries phrases ("hace sol",
/// "cómo te llamas") that no single token's lemma can ever equal.
void main() {
  /// Tokens from a space-separated spec: each item is `text` or `text/lemma`,
  /// laid out one space apart so offsets are realistic.
  List<PangeaToken> tokens(String spec) {
    final out = <PangeaToken>[];
    var offset = 0;
    for (final item in spec.split(' ')) {
      final parts = item.split('/');
      final text = parts.first;
      out.add(
        PangeaToken(
          text: PangeaTokenText(
            content: text,
            offset: offset,
            length: text.characters.length,
          ),
          lemma: Lemma(text: parts.last, saveVocab: true, form: text),
          pos: text == ',' || text == '!' || text == '?' ? 'PUNCT' : 'NOUN',
          morph: {},
        ),
      );
      offset += text.characters.length + 1;
    }
    return out;
  }

  Set<String> texts(Set<PangeaToken> matched) =>
      matched.map((t) => t.text.content).toSet();

  test('nothing matches without a vocab set', () {
    final m = ActivityVocabMatcher(tokens('Hola/hola'), null);
    expect(m.matchedTokens, isEmpty);
    expect(m.matchedEntries, isEmpty);
  });

  test('a single-word entry matches a token by lemma, case-insensitively', () {
    final m = ActivityVocabMatcher(tokens('Llueve/llover mucho/mucho'), {
      'llover',
    });
    expect(texts(m.matchedTokens), {'Llueve'});
    expect(m.matchedEntries, {'llover'});
  });

  test('a phrase matches consecutive tokens by text, across casing', () {
    final m = ActivityVocabMatcher(
      tokens('Hola/hola , Buenos/bueno días/día !'),
      {'buenos días'},
    );
    expect(texts(m.matchedTokens), {'Buenos', 'días'});
    expect(m.matchedEntries, {'buenos días'});
  });

  test('each phrase word may match the token lemma instead of its text', () {
    final m = ActivityVocabMatcher(tokens('voy/ir de/de compras/compra'), {
      'ir de compras',
    });
    expect(texts(m.matchedTokens), {'voy', 'de', 'compras'});
    expect(m.matchedEntries, {'ir de compras'});
  });

  test('punctuation between the words breaks a phrase', () {
    final m = ActivityVocabMatcher(tokens('buenos/bueno , días/día'), {
      'buenos días',
    });
    expect(m.matchedTokens, isEmpty);
    expect(m.matchedEntries, isEmpty);
  });

  test('the words must be in order and adjacent', () {
    expect(
      ActivityVocabMatcher(tokens('días/día buenos/bueno'), {
        'buenos días',
      }).matchedEntries,
      isEmpty,
    );
    expect(
      ActivityVocabMatcher(tokens('buenos/bueno y/y días/día'), {
        'buenos días',
      }).matchedEntries,
      isEmpty,
    );
  });

  test('overlapping phrases are both found', () {
    final m = ActivityVocabMatcher(
      tokens('qué/qué tiempo/tiempo hace/hacer , hace/hacer sol/sol ?'),
      {'qué tiempo hace', 'hace sol'},
    );
    expect(m.matchedEntries, {'qué tiempo hace', 'hace sol'});
    expect(m.matchedTokens.length, 5);
  });

  test('single words and phrases are reported together', () {
    final m = ActivityVocabMatcher(
      tokens('Hola/hola , cómo/cómo estás/estar ?'),
      {'hola', 'cómo estás', 'adiós'},
    );
    expect(texts(m.matchedTokens), {'Hola', 'cómo', 'estás'});
    expect(m.matchedEntries, {'hola', 'cómo estás'});
  });

  test('a phrase longer than the message does not overrun it', () {
    final m = ActivityVocabMatcher(tokens('cómo/cómo'), {'cómo te llamas'});
    expect(m.matchedEntries, isEmpty);
  });
}
