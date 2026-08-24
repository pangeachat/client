import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';

/// ConstructIdentifier equality is strict and consistent with hashCode
/// (#8441). `'other'` is not a wildcard.
void main() {
  ConstructIdentifier id(
    String lemma, {
    ConstructTypeEnum type = ConstructTypeEnum.vocab,
    String category = 'noun',
  }) => ConstructIdentifier(lemma: lemma, type: type, category: category);

  test('equal fields → equal and same hash', () {
    final a = id('casa');
    final b = id('casa');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect({a}.contains(b), isTrue);
  });

  test('category is normalised: case-insensitive, empty == other', () {
    expect(id('casa', category: 'NOUN'), id('casa', category: 'noun'));
    expect(id('casa', category: ''), id('casa', category: 'other'));
    expect(
      id('casa', category: '').hashCode,
      id('casa', category: 'other').hashCode,
    );
    expect(
      {id('casa', category: 'Noun')}.contains(id('casa', category: 'noun')),
      isTrue,
    );
  });

  test('other is not a wildcard', () {
    final other = id('casa', category: 'other');
    final noun = id('casa', category: 'noun');
    expect(other == noun, isFalse);
    expect(noun == other, isFalse);
    expect({noun}.contains(other), isFalse);
    expect({other, noun}.length, 2);
  });

  test('lemma is case-sensitive; type and category distinguish', () {
    expect(id('Casa') == id('casa'), isFalse);
    expect(
      id('bank', category: 'noun') == id('bank', category: 'verb'),
      isFalse,
    );
    expect(
      id('Pres', type: ConstructTypeEnum.morph, category: 'tense') ==
          id('Pres', type: ConstructTypeEnum.vocab, category: 'tense'),
      isFalse,
    );
  });

  test('equality is transitive over categories including other', () {
    // Under the old wildcard: other == noun and other == verb but noun != verb.
    final o = id('bank', category: 'other');
    final n = id('bank', category: 'noun');
    final v = id('bank', category: 'verb');
    expect(o == n, isFalse);
    expect(o == v, isFalse);
    expect(n == v, isFalse);
  });

  test(
    'property: a == b ⇒ a.hashCode == b.hashCode; Set/Map agree with ==',
    () {
      final rng = Random(8441);
      const lemmas = ['casa', 'Casa', 'perro', 'bank'];
      const cats = ['noun', 'NOUN', 'verb', '', 'other', 'Other', 'tense'];
      final corpus = [
        for (var i = 0; i < 300; i++)
          id(
            lemmas[rng.nextInt(lemmas.length)],
            type: ConstructTypeEnum.values[rng.nextInt(2)],
            category: cats[rng.nextInt(cats.length)],
          ),
      ];
      for (final a in corpus) {
        for (final b in corpus) {
          final eq = a == b;
          expect(eq, b == a, reason: 'symmetry $a $b');
          if (eq) expect(a.hashCode, b.hashCode, reason: 'hash contract $a $b');
          expect({a}.contains(b), eq, reason: 'set agrees with == for $a $b');
          expect({a: 1}[b] == 1, eq, reason: 'map agrees with == for $a $b');
        }
      }
    },
  );

  test('round-trips keep identity', () {
    final a = id('casa', category: 'Noun');
    expect(ConstructIdentifier.fromJson(a.toJson()), a);
    expect(ConstructIdentifier.fromString(a.string), a);
    expect(ConstructIdentifier.fromStorageKey(a.storageKey), a);
    expect(ConstructIdentifier.fromTokenParam(a.type, a.toTokenParam()), a);
  });
}
