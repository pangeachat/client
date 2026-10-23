import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/moderation/moderation_refusal.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The body Synapse sends for a Tier-1 refusal (synapse-pangea-chat
/// moderation.instructions.md): the rule's sentence replaces `error`, and the
/// rule id and automated-means flag ride alongside.
MatrixException refusal(String rule, {String? sentence}) =>
    MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': sentence ?? 'Your message was not sent. (server wording)',
      ModerationRefusal.ruleField: rule,
      'chat.pangea.moderation.automated': true,
    });

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await lookupL10n(const Locale('es'));
  });

  group('ModerationRefusal.fromError', () {
    test('reads the rule from a moderation refusal', () {
      final parsed = ModerationRefusal.fromError(
        refusal(ModerationRefusal.contactDetails),
      );
      expect(parsed?.rule, ModerationRefusal.contactDetails);
    });

    test('an M_FORBIDDEN without a rule is a permission failure', () {
      final permissionDenied = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'You are not allowed to send messages here',
      });
      expect(ModerationRefusal.fromError(permissionDenied), isNull);
    });

    test('another errcode is not a refusal even with a rule field', () {
      final rateLimited = MatrixException.fromJson({
        'errcode': 'M_LIMIT_EXCEEDED',
        'error': 'Too many requests',
        ModerationRefusal.ruleField: ModerationRefusal.profanity,
      });
      expect(ModerationRefusal.fromError(rateLimited), isNull);
    });

    test('a non-Matrix error is not a refusal', () {
      expect(ModerationRefusal.fromError(Exception('offline')), isNull);
    });
  });

  group('ModerationRefusal.message', () {
    test('each known rule shows its own copy in the app language', () {
      final contact = ModerationRefusal.fromError(
        refusal(ModerationRefusal.contactDetails),
      )!;
      final profanity = ModerationRefusal.fromError(
        refusal(ModerationRefusal.profanity),
      )!;
      expect(contact.message(l10n), l10n.moderationRefusedContactDetails);
      expect(profanity.message(l10n), l10n.moderationRefusedProfanity);
      expect(contact.message(l10n), isNot(profanity.message(l10n)));
    });

    test('an unknown rule keeps the server sentence', () {
      const sentence = 'Your message was not sent. A new filter applied.';
      final parsed = ModerationRefusal.fromError(
        refusal('some_future_rule', sentence: sentence),
      )!;
      expect(parsed.message(l10n), sentence);
    });
  });
}
