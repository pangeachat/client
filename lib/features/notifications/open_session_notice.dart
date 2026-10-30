import 'package:flutter/foundation.dart';

/// Synapse's notice 30 minutes into a waiting session, saying Pangea Bot takes
/// the open seat at the hour. Opening the session from it offers the bot once
/// (activities.instructions.md, "The start page mirrors the room").
abstract final class OpenSessionNotice {
  /// The notice's variant, which its push carries as `check_in_type`.
  static const checkInType = 'open_session_bot_soon';

  /// The session just opened from the notice, until its waiting room offers
  /// the bot.
  static final ValueNotifier<String?> offerBotIn = ValueNotifier(null);
}
