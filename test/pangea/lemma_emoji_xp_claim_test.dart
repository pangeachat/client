import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/lemma_emoji_setter_mixin.dart';

/// The one-time emoji XP claim (#9005).
///
/// `alreadySet` stands in for [ConstructIdentifier.userSetEmoji], which is read
/// back from analytics room state and so still reads false for a second
/// selection made before the first write has synced. Every case below therefore
/// passes `alreadySet: false` — the bug is exactly the window in which the
/// durable record cannot yet say no.
void main() {
  ConstructIdentifier idFor(String lemma) => ConstructIdentifier(
    lemma: lemma,
    type: ConstructTypeEnum.vocab,
    category: 'noun',
  );

  bool claim(
    ConstructIdentifier id, {
    String accountId = '@alex:staging',
    String language = 'es',
    bool alreadySet = false,
  }) => LemmaEmojiSetter.claimEmojiXP(
    id,
    accountId: accountId,
    language: language,
    alreadySet: alreadySet,
  );

  test(
    'a second selection made before the first has synced does not award',
    () {
      final id = idFor('hablar');

      expect(claim(id), isTrue);
      expect(claim(id), isFalse);
      expect(claim(id), isFalse);
    },
  );

  test('a construct with an emoji already on it does not award', () {
    expect(claim(idFor('comer'), alreadySet: true), isFalse);
  });

  test('each construct is claimed on its own', () {
    expect(claim(idFor('beber')), isTrue);
    expect(claim(idFor('correr')), isTrue);
  });

  test('a claim does not carry across accounts or languages', () {
    final id = idFor('leer');

    expect(claim(id), isTrue);
    expect(claim(id, accountId: '@sam:staging'), isTrue);
    expect(claim(id, language: 'fr'), isTrue);
  });
}
