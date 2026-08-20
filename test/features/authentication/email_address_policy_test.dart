import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/authentication/email_address_policy.dart';

/// Covers pangeachat/synapse-pangea-chat#172. Signup accepted anything holding
/// an '@', so `a@b` passed and Pangea mailed it. This mirrors the homeserver's
/// rule; the two must not drift apart.
void main() {
  group('EmailAddressPolicy.isValid', () {
    test('accepts ordinary addresses', () {
      for (final address in [
        'learner@example.com',
        'a@b.co',
        'user+tag@gmail.com',
        'first.last@mail.example.co.uk',
        'learner@my-school.edu',
        'learner@a.b.c.example.com',
      ]) {
        expect(EmailAddressPolicy.isValid(address), isTrue, reason: address);
      }
    });

    test('refuses the addresses the old presence-and-@ check let through', () {
      for (final address in ['a@b', '@', '@b', 'a@', 'not-an-email', 'a@b.']) {
        expect(EmailAddressPolicy.isValid(address), isFalse, reason: address);
      }
    });

    test('refuses malformed domains', () {
      for (final address in [
        'a@b..co',
        'a@-b.co',
        'a@b-.co',
        'a@b.c',
        'a@b.11',
        'a b@c.de',
        'a@@b.co',
        'a@b.co m',
      ]) {
        expect(EmailAddressPolicy.isValid(address), isFalse, reason: address);
      }
    });

    test('accepts an internationalised domain in either form', () {
      expect(EmailAddressPolicy.isValid('learner@bücher.de'), isTrue);
      expect(EmailAddressPolicy.isValid('learner@xn--bcher-kva.de'), isTrue);
    });

    test('refuses an address longer than mail servers accept', () {
      expect(EmailAddressPolicy.isValid('${'a' * 240}@example.com'), isTrue);
      expect(EmailAddressPolicy.isValid('${'a' * 250}@example.com'), isFalse);
    });
  });
}
