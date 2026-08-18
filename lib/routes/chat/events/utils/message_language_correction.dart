import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/repo/tokens_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Re-assigns the language of a message the detector read wrong, so the
/// reading-assistance modes gated on that language follow the reader's choice.
///
/// The reassignment is persisted the same way a token-info-feedback language
/// correction is — a `pangea.representation` correction child event, never an
/// `m.replace` edit — so anyone in the room may correct anyone's message.
class MessageLanguageCorrection {
  /// The language currently assigned to [messageEvent], or null when it is
  /// unknown or absent from the language store.
  static LanguageModel? assignedLanguage(PangeaMessageEvent messageEvent) =>
      languageFromCode(messageEvent.messageDisplayLangCode);

  /// [langCode] resolved against the language store. A region-tagged code
  /// (`pt-BR`) with no exact store entry resolves to its base language — the
  /// mode gating compares base codes, so a region tag must not read as an
  /// unknown language here either. Store-only -> unit-testable.
  @visibleForTesting
  static LanguageModel? languageFromCode(String langCode) {
    if (langCode == LanguageKeys.unknownLanguage) return null;
    return PLanguageStore.byLangCode(langCode) ??
        PLanguageStore.byLangCode(langCode.split('-').first);
  }

  /// The correction's token payload: [tokens] re-read under [langCode], with
  /// the language pinned at full confidence so [PangeaMessageEvent]'s
  /// correction builder takes the new language off the correction itself.
  /// Pure -> unit-testable.
  @visibleForTesting
  static PangeaMessageTokens correctedTokens(
    List<PangeaToken> tokens,
    String langCode,
  ) => PangeaMessageTokens(
    tokens: tokens,
    detections: [LanguageDetectionModel(langCode: langCode, confidence: 1)],
  );

  /// Re-reads [fullText] under [language] and returns the correction payload.
  ///
  /// The tokenizer is told the language explicitly — left to detect, it would
  /// just reproduce the reading the user is correcting. Throws when the call
  /// fails, so the caller's loading dialog surfaces the error.
  static Future<PangeaMessageTokens> tokenizeAs(
    String fullText,
    LanguageModel language,
  ) async {
    final userController = MatrixState.pangeaController.userController;
    final res = await TokensRepo.instance.get(
      TokensRequestModel(
        fullText: fullText,
        langCode: language.langCode,
        senderL1:
            userController.userL1?.langCode ?? LanguageKeys.unknownLanguage,
        senderL2:
            userController.userL2?.langCode ?? LanguageKeys.unknownLanguage,
      ),
    );

    if (res.isError) throw res.asError!.error;
    return correctedTokens(res.asValue!.value.tokens, language.langCode);
  }

  /// Re-tokenizes [messageEvent]'s display text as [language] and sends the
  /// result as a correction. Re-tokenizing is not optional: the stored tokens
  /// came from the tokenizer model for the language that was read wrong, and a
  /// correction carrying no usable tokens is ignored on read.
  static Future<void> apply(
    PangeaMessageEvent messageEvent,
    LanguageModel language,
  ) async {
    final fullText = messageEvent.messageDisplayText;
    await messageEvent.sendTokenCorrection(
      fullText,
      await tokenizeAs(fullText, language),
    );

    // sendTokenCorrection drops its representation cache before the send, so a
    // rebuild while the event was in flight can have re-cached the pre-
    // correction list. Drop it again so readers see the new language.
    messageEvent.updateLatestEdit();
  }
}
