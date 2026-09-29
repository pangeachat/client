import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// A message Synapse's chat moderation refused before storing it: an
/// `M_FORBIDDEN` that names the rule it applied (synapse-pangea-chat
/// moderation.instructions.md). An `M_FORBIDDEN` without the rule is an
/// ordinary permission failure, not a refusal.
class ModerationRefusal {
  static const String ruleField = 'chat.pangea.moderation.rule';
  static const String contactDetails = 'contact_details';
  static const String profanity = 'profanity';

  final String rule;
  final String serverMessage;

  const ModerationRefusal({required this.rule, required this.serverMessage});

  static ModerationRefusal? fromError(Object error) {
    if (error is! MatrixException || error.error != MatrixError.M_FORBIDDEN) {
      return null;
    }
    final rule = error.raw[ruleField];
    if (rule is! String) return null;
    return ModerationRefusal(rule: rule, serverMessage: error.errorMessage);
  }

  /// The refusal in the learner's app language. A rule this client does not
  /// know keeps the server's own sentence.
  String message(L10n l10n) => switch (rule) {
    contactDetails => l10n.moderationRefusedContactDetails,
    profanity => l10n.moderationRefusedProfanity,
    _ => serverMessage,
  };
}
