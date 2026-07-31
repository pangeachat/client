import 'package:matrix/matrix.dart';

/// Narrows the events scanned by `Room.searchEvents` down to those that carry
/// searchable message text.
///
/// The SDK renders anything else as `Unknown message format of type "<type>"`
/// (or `Redacted`), so state events, attachments and undecryptable events match
/// arbitrary queries unless they are excluded before the text comparison.
class ChatSearchFilter {
  static const Set<String> searchableMessageTypes = {
    MessageTypes.Text,
    MessageTypes.Notice,
    MessageTypes.Emote,
  };

  static bool hasSearchableContent(Event event) =>
      event.type == EventTypes.Message &&
      !event.redacted &&
      searchableMessageTypes.contains(event.messageType);

  static bool matches(Event event, String searchQuery) =>
      hasSearchableContent(event) &&
      event.body.toLowerCase().contains(searchQuery.toLowerCase());
}
