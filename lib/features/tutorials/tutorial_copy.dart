import 'package:flutter/widgets.dart';

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/repo/tokens_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A greeting resolved for the welcome step: the word to show, and — only when
/// it came out of the learner's L2 and the tokenizer answered — the token that
/// makes it renderable as a vocabulary word.
///
/// A null [token] is the instruction to render plain text. It is null on every
/// fallback path, all of which leave the greeting in a language the learner
/// already speaks, where a word bubble would have nothing to teach.
class TutorialGreeting {
  final String word;
  final PangeaToken? token;
  final String? langCode;

  const TutorialGreeting(this.word, {this.token, this.langCode});

  bool get isBubble => token != null && langCode != null;
}

/// Runtime values tutorial copy needs that more than one host has to resolve.
/// The strings themselves stay in the step templates.
class TutorialCopy {
  /// Stands in for the greeting inside the resolved copy, so the tooltip can
  /// find where to put the word bubble.
  ///
  /// The copy stays ONE localized string with a `{greeting}` placeholder: the
  /// host substitutes this marker instead of the word, and the tooltip splits on
  /// it. Splitting the resolved string is what makes the bubble land wherever
  /// the translator put the placeholder, rather than assuming it comes first.
  /// U+2063 (invisible separator) prints nothing if it ever escapes.
  static const String wordSlot = '⁣';

  /// Splits [text] around [wordSlot]: the copy before the word and the copy
  /// after it. Null when the marker is absent, which means the copy was
  /// resolved for plain text and there is nothing to place.
  ///
  /// Split rather than assumed, so the bubble lands wherever the translator put
  /// the `{greeting}` placeholder — English opens with it, and other languages
  /// need not.
  static ({String before, String after})? splitOnWordSlot(String text) {
    final slot = text.indexOf(wordSlot);
    if (slot < 0) return null;
    return (
      before: text.substring(0, slot),
      after: text.substring(slot + wordSlot.length),
    );
  }

  /// A greeting in the learner's target language, borrowed from that locale's
  /// own UI copy rather than a new per-language content source, and tokenized so
  /// it can be shown as a word.
  ///
  /// Falls back to the app language — no bubble — when there is no target
  /// language, when the locale has no translation, or when tokenization fails.
  /// Never throws and never blocks the greeting on the network: a tutorial that
  /// waits on a request is a tutorial that sometimes does not appear.
  ///
  /// Shared because the greeting fires on whichever surface the learner lands
  /// on first — the world map or a course plan.
  static Future<TutorialGreeting> targetLanguageGreeting(
    BuildContext context,
  ) async {
    final fallback = TutorialGreeting(L10n.of(context).welcome);
    final userController = MatrixState.pangeaController.userController;
    final l2 = userController.userL2;
    if (l2 == null) return fallback;

    final String word;
    try {
      word = (await lookupL10n(Locale(l2.langCodeShort))).welcome;
    } catch (_) {
      return fallback;
    }

    try {
      final res = await TokensRepo.instance.get(
        TokensRequestModel(
          fullText: word,
          langCode: l2.langCode,
          senderL1:
              userController.userL1?.langCode ?? LanguageKeys.unknownLanguage,
          senderL2: l2.langCode,
        ),
      );
      if (res.isError) return TutorialGreeting(word);

      final tokens = res.asValue!.value.tokens;
      // One word in, so one token out — anything else means the tokenizer read
      // it as something other than the single word we asked about, and pointing
      // a word card at the first of several would describe the wrong thing.
      if (tokens.length != 1) return TutorialGreeting(word);
      return TutorialGreeting(word, token: tokens.first, langCode: l2.langCode);
    } catch (_) {
      return TutorialGreeting(word);
    }
  }
}
