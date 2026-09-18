import 'package:flutter/widgets.dart';

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/morphs/parts_of_speech_enum.dart';
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

/// The one token in [tokens] that could be a word, or null when there is not
/// exactly one.
///
/// **Punctuation is dropped before counting.** A greeting carries its language's
/// own marks — "¡Bienvenido!", "Bonjour !" — and the tokenizer returns those as
/// tokens of their own, so counting raw tokens rejected every punctuated
/// greeting and silently degraded it to plain, untappable text. What has to be
/// unambiguous is the WORD: exactly one thing here can be a lemma, or the word
/// card would be pointed at a guess.
@visibleForTesting
PangeaToken? soleLemmaToken(List<PangeaToken> tokens) {
  final words = tokens
      .where((token) => PartOfSpeechEnum.isEligibleLemmaTag(token.pos))
      .toList();
  return words.length == 1 ? words.first : null;
}

/// Runtime values tutorial copy needs that more than one host has to resolve.
/// The strings themselves stay in the step templates.
class TutorialCopy {
  /// A greeting in the learner's target language, borrowed from that locale's
  /// own UI copy rather than a new per-language content source, and tokenized so
  /// it can be shown as a word.
  ///
  /// The borrowed string is [L10n.joinedCourseStepTitle] — "Welcome!" — chosen
  /// because it is the one bare greeting already translated into every locale
  /// **with that language's own punctuation**: the Spanish inverted opening
  /// mark, the French space before the exclamation, the Japanese fullwidth one.
  /// A new key would have read as English for every learner until 116 locales
  /// were translated. It is shared copy, so the ARB carries a note not to turn
  /// it into a course-specific sentence.
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
    final fallback = TutorialGreeting(L10n.of(context).joinedCourseStepTitle);
    final userController = MatrixState.pangeaController.userController;
    final l2 = userController.userL2;
    if (l2 == null) return fallback;

    final String word;
    try {
      word = (await lookupL10n(Locale(l2.langCodeShort))).joinedCourseStepTitle;
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

      final token = soleLemmaToken(res.asValue!.value.tokens);
      if (token == null) return TutorialGreeting(word);
      // The bubble shows [word] — punctuation and all — while the card and the
      // collection use this token, which is the word without it.
      return TutorialGreeting(word, token: token, langCode: l2.langCode);
    } catch (_) {
      return TutorialGreeting(word);
    }
  }
}
