import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/repo/tokens_repo.dart';

/// CLIENT-EBS (#9071): a representation with no text still asked choreo to
/// tokenize it, and choreo answered the empty body with a 422. The repo now
/// answers empty text itself, with no request — so this test needs no network
/// and no app state, which is also what proves nothing was sent.
void main() {
  test(
    'empty or whitespace-only text yields no tokens and no request',
    () async {
      for (final text in ['', '   ', '\n\t']) {
        final res = await TokensRepo.instance.get(
          TokensRequestModel(
            fullText: text,
            langCode: 'unk',
            senderL1: 'ar',
            senderL2: 'en',
          ),
        );
        expect(res.isValue, isTrue, reason: 'text: "$text"');
        expect(res.asValue!.value.tokens, isEmpty);
        expect(res.asValue!.value.lang, 'unk');
      }
    },
  );
}
